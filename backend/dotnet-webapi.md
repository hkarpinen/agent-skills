# dotnet-webapi

> Opinionated .NET Web API backend stack — package choices, project structure, and implementation conventions.

**When to use this skill**: building, scaffolding, or asking about a .NET Web API project,
including package selection, project structure, DI wiring, EF Core setup, Serilog, FluentValidation,
ASP.NET Core Identity, OpenTelemetry, or HTTP resiliency.

**Does not apply to**: console apps (use `dotnet-console`), background workers (use `dotnet-worker`).

**Composes with**: `righting-software` (architecture principles — this skill covers .NET implementation only and does not repeat layer rules, naming conventions, or anti-patterns), and a DB bridge skill (e.g. `dotnet-efcore-postgres`) that supplies the DB provider configuration.

**DB provider**: not specified here. Supplied by a bridge skill (e.g. `dotnet-efcore-postgres`).

---

## Package Summary

| Layer | Key packages |
|---|---|
| Client (Host) | `Swashbuckle.AspNetCore`, `FluentValidation.AspNetCore` |
| Application | *(none — pure orchestration)* |
| Domain | `Ardalis.GuardClauses` |
| Infrastructure | `Microsoft.EntityFrameworkCore`, `Microsoft.AspNetCore.Identity.EntityFrameworkCore`, `Microsoft.AspNetCore.Authentication.JwtBearer`, `Microsoft.Extensions.Http.Resilience` |
| Infrastructure (DB provider) | supplied by bridge skill |
| Cross-cutting | `Serilog.AspNetCore`, `OpenTelemetry.Extensions.Hosting` |

### Full Package List by Layer

**Client (YourApp.Host.Api)**
| Package | Purpose |
|---|---|
| `Swashbuckle.AspNetCore` | Swagger UI and OpenAPI spec |
| `Microsoft.AspNetCore.OpenApi` | OpenAPI metadata for Minimal APIs |
| `FluentValidation.AspNetCore` | Validator registration and DI integration |

**Application (YourApp.Application)**
No additional packages. Managers are pure orchestration.

**Domain (YourApp.Domain)**
| Package | Purpose |
|---|---|
| `Ardalis.GuardClauses` | Guard clause helpers for invariant enforcement |

**Infrastructure (YourApp.Infrastructure)**
| Package | Purpose |
|---|---|
| `Microsoft.EntityFrameworkCore` | Core EF |
| `Microsoft.EntityFrameworkCore.Tools` | Migrations CLI (`dotnet ef`) |
| `Microsoft.EntityFrameworkCore.Design` | Design-time tooling |
| `Microsoft.AspNetCore.Identity.EntityFrameworkCore` | Identity with EF Core persistence |
| `Microsoft.AspNetCore.Authentication.JwtBearer` | JWT bearer token validation |
| `System.IdentityModel.Tokens.Jwt` | JWT token generation |
| `Microsoft.Extensions.Http.Resilience` | Polly v8 wrapper for outbound HttpClient |

> **DB provider package** (e.g. `Npgsql.EntityFrameworkCore.PostgreSQL`) is supplied
> by the bridge skill. Do not add a provider package to `YourApp.Infrastructure` directly.

**Cross-cutting (YourApp.Utilities)**
| Package | Purpose |
|---|---|
| `Serilog.AspNetCore` | Serilog host integration |
| `Serilog.Sinks.Console` | Console sink |
| `Serilog.Sinks.File` | File sink |
| `Serilog.Enrichers.Environment` | Environment/machine name enrichment |
| `Serilog.Enrichers.Thread` | Thread ID enrichment |
| `OpenTelemetry.Extensions.Hosting` | OTel hosting integration |
| `OpenTelemetry.Instrumentation.AspNetCore` | HTTP request tracing |
| `OpenTelemetry.Instrumentation.Http` | Outbound HTTP tracing |
| `OpenTelemetry.Instrumentation.EntityFrameworkCore` | EF Core query tracing |
| `OpenTelemetry.Exporter.OpenTelemetryProtocol` | OTLP exporter |

**Test Projects**
| Package | Purpose |
|---|---|
| `xunit` + `xunit.runner.visualstudio` | Test framework |
| `Moq` | Mocking |
| `FluentAssertions` | Assertion library |
| `FluentValidation.TestHelper` | Validator unit testing |
| `Testcontainers.MsSql` / `Testcontainers.PostgreSql` | Real DB in Docker |
| `coverlet.collector` | Code coverage collection |
| `Microsoft.AspNetCore.Mvc.Testing` | WebApplicationFactory for Host tests |

---

## Project Structure

Each DDD layer is a separate class library. The host is the only executable and the
composition root. Nothing references the host. The host references everything.

```
YourApp.sln
│
├── src/
│   │
│   │   ── CLIENT LAYER ──────────────────────────────────────
│   ├── YourApp.Host.Api/             ← ASP.NET Core Web API host (executable)
│   │   ├── Endpoints/                ← Minimal API endpoint definitions
│   │   ├── Validators/               ← FluentValidation validators
│   │   ├── Middleware/               ← Exception handling, correlation ID
│   │   ├── Extensions/               ← DI wiring (calls each library's extension)
│   │   └── Program.cs
│   │
│   │   ── APPLICATION LAYER ──────────────────────────────────
│   ├── YourApp.Application/          ← Class library — Managers
│   │   ├── Orders/
│   │   │   └── OrderWorkflowManager.cs
│   │   └── ServiceExtensions.cs
│   │
│   │   ── DOMAIN LAYER ──────────────────────────────────────
│   ├── YourApp.Domain/               ← Class library — Engines, entities, value objects, aggregates
│   │   ├── Engines/
│   │   │   └── Pricing/
│   │   │       └── TieredPricingEngine.cs
│   │   ├── Orders/
│   │   │   ├── Order.cs
│   │   │   ├── OrderLine.cs
│   │   │   └── Events/
│   │   │       └── OrderConfirmed.cs
│   │   ├── Shared/
│   │   │   └── Money.cs
│   │   └── ServiceExtensions.cs
│   │
│   │   ── INFRASTRUCTURE LAYER ──────────────────────────────
│   ├── YourApp.Infrastructure/       ← Class library — Resource Access, EF Core, gateways
│   │   ├── Persistence/
│   │   │   ├── AppDbContext.cs
│   │   │   └── Configurations/       ← IEntityTypeConfiguration<T> per entity
│   │   ├── Orders/
│   │   │   ├── OrderRepository.cs
│   │   │   └── OrderEntity.cs        ← ORM model, never leaves this project
│   │   ├── Identity/
│   │   │   ├── AppUser.cs
│   │   │   └── JwtTokenService.cs
│   │   └── ServiceExtensions.cs
│   │
│   │   ── CROSS-CUTTING ─────────────────────────────────────
│   └── YourApp.Utilities/            ← Class library — logging helpers, guards, config
│       └── ServiceExtensions.cs
│
└── tests/
    ├── YourApp.Domain.Tests/
    ├── YourApp.Application.Tests/
    ├── YourApp.Infrastructure.Tests/
    └── YourApp.Host.Api.Tests/
```

## Project Reference Graph

```
YourApp.Host.Api       ──►  YourApp.Application
                            YourApp.Domain
                            YourApp.Infrastructure
                            YourApp.Utilities

YourApp.Application    ──►  YourApp.Domain
                            YourApp.Utilities

YourApp.Domain         ──►  YourApp.Utilities

YourApp.Infrastructure ──►  YourApp.Domain
                            YourApp.Utilities

YourApp.Utilities      ──►  (nothing)
```

The compiler enforces the call direction rules from `righting-software`.
A `YourApp.Domain` reference to `YourApp.Infrastructure` is a build error.

---

## DI Convention

Each library owns a `ServiceExtensions.cs` with a single `IServiceCollection` extension
method. The host calls each one — it registers nothing directly.

```csharp
// YourApp.Host.Api/Program.cs
// dbOptions is provided by the bridge skill (e.g. dotnet-efcore-postgres)
builder.Services
    .AddUtilities()
    .AddDomain()
    .AddApplication()
    .AddInfrastructure(builder.Configuration, dbOptions)
    .AddApiValidation();
```

Lifetimes: Managers → `Scoped`, Engines → `Scoped`, Repositories → `Scoped`, Utilities → `Singleton`.

---

## Client Layer Implementation

### Minimal API Conventions
- Group related endpoints into static extension classes, one per use case cluster.
- Use `TypedResults` for all responses — enables Swagger schema inference.
- Return `ProblemDetails` for all errors via built-in problem details middleware.
- Use `[AsParameters]` for binding complex query or route parameter objects.
- Endpoint methods: validate input → call Manager → return result. Nothing else.

```csharp
// Endpoints/OrderEndpoints.cs
public static class OrderEndpoints
{
    public static IEndpointRouteBuilder MapOrderEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/orders").RequireAuthorization();
        group.MapPost("/", PlaceOrder);
        group.MapGet("/{id:guid}", GetOrder);
        return app;
    }

    private static async Task<Results<Created<OrderResponse>, ValidationProblem>> PlaceOrder(
        PlaceOrderRequest request,
        IValidator<PlaceOrderRequest> validator,
        IOrderWorkflowManager manager,
        CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(request, ct);
        if (!validation.IsValid)
            return TypedResults.ValidationProblem(validation.ToDictionary());

        var result = await manager.PlaceOrderAsync(request.ToCommand(), ct);
        return TypedResults.Created($"/orders/{result.OrderId}", result.ToResponse());
    }
}
```

### FluentValidation at the Client Boundary
Validators live in `YourApp.Host.Api/Validators/` — one per request type.
Run in endpoints only, before any Manager is called.
Never use `[ApiController]` automatic validation — call validators explicitly.

```csharp
public class PlaceOrderRequestValidator : AbstractValidator<PlaceOrderRequest>
{
    public PlaceOrderRequestValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty();
        RuleFor(x => x.Lines).NotEmpty().WithMessage("Order must have at least one line.");
        RuleForEach(x => x.Lines).ChildRules(line =>
        {
            line.RuleFor(l => l.ProductId).NotEmpty();
            line.RuleFor(l => l.Quantity).GreaterThan(0);
        });
    }
}
```

### Host Registration

```csharp
// Program.cs
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .CreateBootstrapLogger();

builder.Host.UseSerilog((ctx, services, config) => config
    .ReadFrom.Configuration(ctx.Configuration)
    .ReadFrom.Services(services));

builder.Services
    .AddUtilities()
    .AddDomain()
    .AddApplication()
    .AddInfrastructure(builder.Configuration, dbOptions)
    .AddApiValidation()
    .AddEndpointsApiExplorer()
    .AddSwaggerGen();

var app = builder.Build();
app.UseExceptionHandler();
app.UseSerilogRequestLogging();
app.UseAuthentication();
app.UseAuthorization();
app.MapOrderEndpoints();
app.Run();
```

---

## Application Layer Implementation

Managers are `internal sealed` classes implementing a public contract. Constructor injection only.

```csharp
// Orders/OrderWorkflowManager.cs
internal sealed class OrderWorkflowManager : IOrderWorkflowManager
{
    private readonly IOrderRepository _orders;
    private readonly IPricingEngine _pricing;
    private readonly ILogger<OrderWorkflowManager> _logger;

    public OrderWorkflowManager(
        IOrderRepository orders, IPricingEngine pricing,
        ILogger<OrderWorkflowManager> logger)
    {
        _orders = orders;
        _pricing = pricing;
        _logger = logger;
    }

    public async Task<PlaceOrderResult> PlaceOrderAsync(PlaceOrderCommand command, CancellationToken ct)
    {
        _logger.LogInformation("Placing order for customer {CustomerId}", command.CustomerId);
        var price = _pricing.CalculatePrice(command.ToPricingContext());
        var order = Order.Create(command.CustomerId, command.Lines, price);
        await _orders.SaveAsync(order, ct);
        foreach (var evt in order.DomainEvents)
            await _eventDispatcher.DispatchAsync(evt, ct);
        order.ClearEvents();
        _logger.LogInformation("Order {OrderId} placed", order.Id);
        return new PlaceOrderResult(order.Id);
    }
}

// ServiceExtensions.cs
public static class ApplicationServiceExtensions
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IOrderWorkflowManager, OrderWorkflowManager>();
        return services;
    }
}
```

---

## Domain Layer Implementation

Engines are `internal sealed`, stateless, and implement a public contract.
Entities use `record` for value objects and raise domain events via private event lists.
Domain models carry zero EF Core attributes or infrastructure references.

```csharp
// Engines/Pricing/TieredPricingEngine.cs
internal sealed class TieredPricingEngine : IPricingEngine
{
    public Money CalculatePrice(PricingContext context)
    {
        Guard.Against.Null(context);
        return context.CustomerTier switch
        {
            CustomerTier.Gold   => context.BasePrice * 0.85m,
            CustomerTier.Silver => context.BasePrice * 0.92m,
            _                   => context.BasePrice
        };
    }
}

// Orders/Order.cs
public class Order
{
    private readonly List<IDomainEvent> _events = new();
    public OrderId Id { get; }
    public CustomerId CustomerId { get; }
    public OrderStatus Status { get; private set; }
    public IReadOnlyList<IDomainEvent> DomainEvents => _events.AsReadOnly();

    public void Confirm()
    {
        Guard.Against.InvalidInput(Status, nameof(Status),
            s => s == OrderStatus.Pending, "Order must be pending to confirm.");
        Status = OrderStatus.Confirmed;
        _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
    }
    public void ClearEvents() => _events.Clear();
}

// Shared/Money.cs — value object
public record Money(decimal Amount, Currency Currency)
{
    public Money Add(Money other)
    {
        Guard.Against.InvalidInput(other.Currency, nameof(other),
            c => c == Currency, "Currency mismatch.");
        return this with { Amount = Amount + other.Amount };
    }
}

// Orders/Events/OrderConfirmed.cs
public record OrderConfirmed(OrderId OrderId, DateTime ConfirmedAt);

// ServiceExtensions.cs
public static class DomainServiceExtensions
{
    public static IServiceCollection AddDomain(this IServiceCollection services)
    {
        services.AddScoped<IPricingEngine, TieredPricingEngine>();
        services.AddScoped<IFraudDetectionEngine, RuleBasedFraudDetectionEngine>();
        return services;
    }
}
```

---

## Infrastructure Layer Implementation

All EF Core, Identity, and HTTP client code lives here and nowhere else.
`DbContext` never leaves this project.

### EF Core Rules
- Prefer LINQ over raw SQL. Use raw SQL only when there is a measurable, non-negligible
  performance difference — document the reason in a comment at the call site.
- Use `IEntityTypeConfiguration<T>` per entity — no data annotations on domain models.
- Use owned types (`OwnsOne`) to persist value objects as columns in the parent table.

```csharp
// Persistence/AppDbContext.cs
public class AppDbContext : IdentityDbContext<AppUser>
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }
    public DbSet<OrderEntity> Orders => Set<OrderEntity>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        // Identity tables → separate schema
        builder.Entity<AppUser>().ToTable("Users", "identity");
        builder.Entity<IdentityRole>().ToTable("Roles", "identity");
        builder.Entity<IdentityUserRole<string>>().ToTable("UserRoles", "identity");
        builder.Entity<IdentityUserClaim<string>>().ToTable("UserClaims", "identity");
        builder.Entity<IdentityUserLogin<string>>().ToTable("UserLogins", "identity");
        builder.Entity<IdentityRoleClaim<string>>().ToTable("RoleClaims", "identity");
        builder.Entity<IdentityUserToken<string>>().ToTable("UserTokens", "identity");
    }
}

// Persistence/Configurations/OrderEntityConfiguration.cs
public class OrderEntityConfiguration : IEntityTypeConfiguration<OrderEntity>
{
    public void Configure(EntityTypeBuilder<OrderEntity> builder)
    {
        builder.ToTable("Orders", schema: "orders");
        builder.HasKey(o => o.Id);
        builder.Property(o => o.Status).HasConversion<string>().HasMaxLength(50);
        builder.OwnsOne(o => o.TotalAmount, money =>
        {
            money.Property(m => m.Amount).HasColumnName("TotalAmount").HasColumnType("decimal(18,4)");
            money.Property(m => m.Currency).HasColumnName("TotalCurrency").HasMaxLength(3);
        });
    }
}

// Orders/OrderRepository.cs
internal sealed class OrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;
    public OrderRepository(AppDbContext db) => _db = db;

    public async Task<Order?> GetAsync(OrderId id, CancellationToken ct = default)
        => await _db.Orders
            .Include(o => o.Lines)
            .Where(o => o.Id == id.Value)
            .Select(o => o.ToDomain())
            .FirstOrDefaultAsync(ct);

    public async Task SaveAsync(Order order, CancellationToken ct = default)
    {
        _db.Orders.Update(order.ToEntity());
        await _db.SaveChangesAsync(ct);
    }
}
```

### Migrations
```bash
dotnet ef migrations add <Name> \
  --project YourApp.Infrastructure \
  --startup-project YourApp.Host.Api

dotnet ef database update \
  --project YourApp.Infrastructure \
  --startup-project YourApp.Host.Api
```
Apply migrations at startup in development only. In production, apply via CI/CD pipeline.

### ASP.NET Core Identity + JWT
Identity tables live in the `identity` schema. `AppUser` never leaves this project —
map to a domain `UserId` value object at the repository boundary.

```csharp
// Identity/AppUser.cs
public class AppUser : IdentityUser
{
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
}

// Identity/JwtTokenService.cs
internal sealed class JwtTokenService : ITokenService
{
    private readonly JwtSettings _settings;
    public JwtTokenService(IOptions<JwtSettings> settings) => _settings = settings.Value;

    public string GenerateToken(AppUser user, IList<string> roles)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id),
            new(ClaimTypes.Email, user.Email!),
        };
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_settings.Secret));
        var token = new JwtSecurityToken(
            issuer: _settings.Issuer, audience: _settings.Audience, claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_settings.ExpiryMinutes),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
```

### HTTP Resiliency
All outbound `HttpClient` calls use named clients registered here.
Use `AddStandardResilienceHandler()` — provides retries, circuit breaker, and timeout.
Configure per client, never globally.

```csharp
services.AddHttpClient<IPaymentGateway, StripePaymentGateway>(client =>
    client.BaseAddress = new Uri(configuration["Stripe:BaseUrl"]!))
    .AddStandardResilienceHandler();
```

### Infrastructure Registration

```csharp
// ServiceExtensions.cs
public static class InfrastructureServiceExtensions
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        Action<DbContextOptionsBuilder> dbOptions)
    {
        services.AddDbContext<AppDbContext>(dbOptions);

        services.AddIdentity<AppUser, IdentityRole>(options =>
        {
            options.Password.RequiredLength = 12;
            options.Lockout.MaxFailedAccessAttempts = 5;
            options.User.RequireUniqueEmail = true;
        })
        .AddEntityFrameworkStores<AppDbContext>()
        .AddDefaultTokenProviders();

        services.AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
            options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
        })
        .AddJwtBearer(options =>
        {
            var jwt = configuration.GetSection("Jwt").Get<JwtSettings>()!;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true, ValidateAudience = true,
                ValidateLifetime = true, ValidateIssuerSigningKey = true,
                ValidIssuer = jwt.Issuer, ValidAudience = jwt.Audience,
                IssuerSigningKey = new SymmetricSecurityKey(
                    Encoding.UTF8.GetBytes(jwt.Secret)),
                ClockSkew = TimeSpan.Zero
            };
        });

        services.AddScoped<IOrderRepository, OrderRepository>();
        services.AddScoped<ITokenService, JwtTokenService>();
        return services;
    }
}
```

---

## Cross-cutting Implementation

### Serilog
Structured logging always — no string interpolation in log messages.
Log at Manager entry/exit for workflow tracing. Log at catch site with full context.

```csharp
// ✅ Always structured
_logger.LogInformation("Order {OrderId} confirmed for customer {CustomerId}", orderId, customerId);

// ❌ Never interpolated
_logger.LogInformation($"Order {orderId} confirmed");
```

```json
// appsettings.json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": { "Microsoft": "Warning", "Microsoft.EntityFrameworkCore": "Warning" }
    }
  }
}
```

### OpenTelemetry

```csharp
services.AddOpenTelemetry()
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddOtlpExporter())
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddOtlpExporter());
```

Configure via environment variables:
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_SERVICE_NAME=YourApp
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```
