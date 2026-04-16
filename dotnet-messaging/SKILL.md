---
name: dotnet-messaging
description: Bridge between messaging patterns and .NET — outbox implementation with EF Core, hosted service for outbox publishing, MassTransit consumer setup, and idempotent consumer wiring. Use when implementing the outbox pattern in a .NET application, setting up event consumers, or configuring MassTransit with RabbitMQ or the in-memory transport. Compose with `messaging` for the transport-agnostic patterns and `ddd-strategic-patterns` for event design.
---

## Scope

This skill owns the **.NET realization of messaging patterns**. It specifies:

- Outbox entity and EF Core configuration
- `IHostedService` for outbox polling
- MassTransit consumer registration and configuration
- Idempotent consumer base class
- Integration test patterns for messaging

It does **not** cover:
- Transport-agnostic patterns (outbox theory, envelopes, idempotency rationale) — see `messaging`
- Which events to publish or subscribe to — see `ddd-strategic-patterns`
- Broker-specific infrastructure (Docker Compose for RabbitMQ) — see `docker`

---

## Outbox Entity

```csharp
// Domain or Infrastructure — depends on architecture bridge
public class OutboxMessage
{
    public Guid Id { get; init; }
    public string EventType { get; init; } = string.Empty;
    public string Payload { get; init; } = string.Empty;  // JSON
    public DateTimeOffset CreatedAt { get; init; }
    public bool Published { get; set; }
    public DateTimeOffset? PublishedAt { get; set; }
}
```

EF Core configuration (in the Infrastructure layer alongside entity configs):

```csharp
public class OutboxMessageConfiguration : IEntityTypeConfiguration<OutboxMessage>
{
    public void Configure(EntityTypeBuilder<OutboxMessage> builder)
    {
        builder.ToTable("outbox");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Payload).HasColumnType("jsonb");
        builder.HasIndex(x => x.CreatedAt)
            .HasFilter("published = false")
            .HasDatabaseName("ix_outbox_unpublished");
    }
}
```

---

## Writing to the Outbox

The application layer writes outbox records in the same transaction as the aggregate save. Extract domain events from the aggregate and serialize them.

```csharp
// Infrastructure — called by the repository's SaveAsync or a SaveChanges interceptor
public static class OutboxExtensions
{
    public static void AddToOutbox(
        this DbContext context,
        string source,
        IEnumerable<IDomainEvent> events,
        JsonSerializerOptions jsonOptions)
    {
        foreach (var domainEvent in events)
        {
            var message = new OutboxMessage
            {
                Id = Guid.NewGuid(),
                EventType = $"{source}.{domainEvent.GetType().Name.ToSnakeCase()}",
                Payload = JsonSerializer.Serialize(domainEvent, domainEvent.GetType(), jsonOptions),
                CreatedAt = DateTimeOffset.UtcNow,
                Published = false
            };
            context.Set<OutboxMessage>().Add(message);
        }
    }
}
```

Rules:
- Call `AddToOutbox` **before** `SaveChangesAsync` so both the aggregate and the outbox record are in the same transaction.
- Use `System.Text.Json` with `JsonSerializerOptions` configured for snake_case to match the envelope format.
- The `source` parameter is the bounded context name (e.g., `"identity"`, `"forum"`).

---

## Outbox Publisher — Hosted Service

A background `IHostedService` polls the outbox and publishes via whatever transport is configured.

```csharp
internal sealed class OutboxPublisher : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IPublishEndpoint _publishEndpoint;  // MassTransit or custom
    private readonly ILogger<OutboxPublisher> _logger;
    private readonly TimeSpan _pollingInterval = TimeSpan.FromSeconds(5);

    public OutboxPublisher(
        IServiceScopeFactory scopeFactory,
        IPublishEndpoint publishEndpoint,
        ILogger<OutboxPublisher> logger)
    {
        _scopeFactory = scopeFactory;
        _publishEndpoint = publishEndpoint;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await ProcessOutboxAsync(ct);
            await Task.Delay(_pollingInterval, ct);
        }
    }

    private async Task ProcessOutboxAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var messages = await db.Set<OutboxMessage>()
            .Where(m => !m.Published)
            .OrderBy(m => m.CreatedAt)
            .Take(50)
            .ToListAsync(ct);

        foreach (var message in messages)
        {
            try
            {
                await _publishEndpoint.Publish<EventEnvelope>(
                    new { message.Id, message.EventType, message.Payload, message.CreatedAt },
                    ct);

                message.Published = true;
                message.PublishedAt = DateTimeOffset.UtcNow;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to publish outbox message {MessageId}", message.Id);
                break;  // Stop on first failure to preserve ordering
            }
        }

        if (messages.Any(m => m.Published))
            await db.SaveChangesAsync(ct);
    }
}
```

Rules:
- Register as `services.AddHostedService<OutboxPublisher>()` in the host project.
- Use `IServiceScopeFactory` — `BackgroundService` is a singleton; `DbContext` is scoped.
- Break on first failure to preserve ordering within the publisher batch.
- Tune `_pollingInterval` and batch size (`Take(50)`) based on throughput needs.

---

## MassTransit — Transport Configuration

MassTransit abstracts the broker. Configure it once; swap transports by changing the registration.

```csharp
// RabbitMQ (production)
services.AddMassTransit(x =>
{
    x.AddConsumersFromNamespaceContaining<UserRegisteredConsumer>();

    x.UsingRabbitMq((context, cfg) =>
    {
        cfg.Host(configuration["RabbitMq:Host"], h =>
        {
            h.Username(configuration["RabbitMq:Username"]!);
            h.Password(configuration["RabbitMq:Password"]!);
        });
        cfg.ConfigureEndpoints(context);
    });
});

// In-memory (development / tests)
services.AddMassTransit(x =>
{
    x.AddConsumersFromNamespaceContaining<UserRegisteredConsumer>();
    x.UsingInMemory((context, cfg) => cfg.ConfigureEndpoints(context));
});
```

Rules:
- Use `AddConsumersFromNamespaceContaining<T>()` to auto-register all consumers in the assembly.
- Use `UsingInMemory` for integration tests and local development without a broker.
- Never hardcode broker credentials — inject via configuration / environment variables.
- MassTransit handles retry, dead-letter, and serialization. Configure retry policy per consumer if needed.

---

## Consumer — Idempotent Base Pattern

```csharp
public class UserRegisteredConsumer : IConsumer<UserRegisteredEvent>
{
    private readonly ForumDbContext _db;

    public UserRegisteredConsumer(ForumDbContext db) => _db = db;

    public async Task Consume(ConsumeContext<UserRegisteredEvent> context)
    {
        var evt = context.Message;

        // Upsert is naturally idempotent — no deduplication table needed
        var existing = await _db.ForumUsers.FindAsync(evt.UserId);
        if (existing is null)
        {
            _db.ForumUsers.Add(new ForumUser
            {
                Id = evt.UserId,
                DisplayName = evt.DisplayName,
                AvatarUrl = evt.AvatarUrl
            });
        }
        else
        {
            existing.DisplayName = evt.DisplayName;
            existing.AvatarUrl = evt.AvatarUrl;
        }

        await _db.SaveChangesAsync();
    }
}
```

For non-idempotent operations, use the deduplication table approach from `messaging`:

```csharp
public async Task Consume(ConsumeContext<SomeEvent> context)
{
    var eventId = context.MessageId ?? Guid.NewGuid();

    if (await _db.ProcessedEvents.AnyAsync(e => e.EventId == eventId))
        return;

    // Apply business logic...

    _db.ProcessedEvents.Add(new ProcessedEvent { EventId = eventId });
    await _db.SaveChangesAsync();
}
```

---

## Packages

| Package | Purpose |
|---|---|
| `MassTransit` | Core abstractions (publish, consume, saga) |
| `MassTransit.RabbitMQ` | RabbitMQ transport |
| `MassTransit.EntityFrameworkCore` | EF Core outbox integration (alternative to hand-rolled outbox) |
| `MassTransit.Abstractions` | Shared message contracts |

MassTransit ships its own outbox implementation (`cfg.UseEntityFrameworkOutbox()`). Use it instead of hand-rolling when MassTransit is your transport. The hand-rolled outbox from the `messaging` skill is for systems that do not use MassTransit or want broker independence.

---

## Testing Consumers

Use the in-memory transport for integration tests:

```csharp
// In your WebApplicationFactory or test setup
services.AddMassTransitTestHarness(x =>
{
    x.AddConsumer<UserRegisteredConsumer>();
});

// In the test
var harness = scope.ServiceProvider.GetRequiredService<ITestHarness>();
await harness.Start();

await harness.Bus.Publish(new UserRegisteredEvent
{
    UserId = Guid.NewGuid(),
    DisplayName = "Test User",
    AvatarUrl = null
});

// Assert the consumer processed it
(await harness.Consumed.Any<UserRegisteredEvent>()).Should().BeTrue();
```

---

## Companion Skills

| When you need | Skill |
|---|---|
| Transport-agnostic messaging patterns (outbox, envelopes, idempotency) | `messaging` |
| Decide what events exist and which contexts publish/subscribe | `ddd-strategic-patterns` |
| Event payload schema format and versioning | `ddd-strategic-patterns` (see `references/EVENT-SCHEMAS.md`) |
| Wire the outbox table to PostgreSQL | `dotnet-efcore-postgres` + `db-postgres` |
