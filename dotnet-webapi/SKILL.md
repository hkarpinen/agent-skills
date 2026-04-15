---
name: dotnet-webapi
description: Opinionated .NET Web API backend stack — package choices, project structure, and implementation conventions. Use when building, scaffolding, or asking about a .NET Web API project, including package selection, project structure, DI wiring, EF Core setup, Serilog, FluentValidation, ASP.NET Core Identity, OpenTelemetry, or HTTP resiliency. Does not apply to console apps or background workers. Composes with righting-software for architecture principles and a DB bridge skill (e.g. dotnet-efcore-postgres) for DB provider configuration.
---

## Core Package Stack

| Layer | Key packages |
|---|---|
| Client (Host) | `Swashbuckle.AspNetCore`, `FluentValidation.AspNetCore` |
| Application | *(none — pure orchestration)* |
| Domain | `Ardalis.GuardClauses` |
| Infrastructure | `Microsoft.EntityFrameworkCore`, `Microsoft.AspNetCore.Identity.EntityFrameworkCore`, `Microsoft.AspNetCore.Authentication.JwtBearer` |
| Cross-cutting | `Serilog.AspNetCore`, `OpenTelemetry.Extensions.Hosting` |

See [references/PACKAGES.md](references/PACKAGES.md) for the complete package list by layer.

---

## Project Structure

Each DDD layer is a separate class library. The host is the only executable and the composition root.

```
YourApp.sln
├── src/
│   ├── YourApp.Host.Api/             ← Client layer (executable)
│   ├── YourApp.Application/          ← Application layer (Managers)
│   ├── YourApp.Domain/               ← Domain layer (Engines, entities, value objects)
│   ├── YourApp.Infrastructure/       ← Infrastructure layer (Resource Access, EF Core)
│   └── YourApp.Utilities/            ← Cross-cutting (logging, config)
└── tests/
    ├── YourApp.Domain.Tests/
    ├── YourApp.Application.Tests/
    ├── YourApp.Infrastructure.Tests/
    └── YourApp.Host.Api.Tests/
```

**Project Reference Graph**:
```
Host.Api → Application, Domain, Infrastructure, Utilities
Application → Domain, Utilities
Domain → Utilities
Infrastructure → Domain, Utilities
Utilities → (nothing)
```

The compiler enforces call direction rules from `righting-software`.

---

## DI Convention

Each library owns a `ServiceExtensions.cs` with one `IServiceCollection` extension method. The host calls each — it registers nothing directly.

```csharp
// Program.cs
builder.Services
    .AddUtilities()
    .AddDomain()
    .AddApplication()
    .AddInfrastructure(builder.Configuration, dbOptions)
    .AddApiValidation();
```

Lifetimes: Managers → `Scoped`, Engines → `Scoped`, Repositories → `Scoped`, Utilities → `Singleton`.

---

## Client Layer — Controllers

- One controller per use case cluster (e.g., `OrdersController`, `CustomersController`)
- Use `[ApiController]` attribute for automatic model validation
- Return `ActionResult<T>` for typed responses
- Validate → call Manager → return result. Nothing else.
- Use attribute routing: `[Route("api/[controller]")]`

```csharp
[ApiController]
[Route("api/orders")]
[Authorize]
public class OrdersController : ControllerBase
{
    private readonly IOrderWorkflowManager _manager;
    private readonly IValidator<PlaceOrderRequest> _validator;

    public OrdersController(IOrderWorkflowManager manager, IValidator<PlaceOrderRequest> validator)
    {
        _manager = manager;
        _validator = validator;
    }

    [HttpPost]
    public async Task<ActionResult<OrderResponse>> PlaceOrder(
        [FromBody] PlaceOrderRequest request,
        CancellationToken ct)
    {
        var validation = await _validator.ValidateAsync(request, ct);
        if (!validation.IsValid)
            return ValidationProblem(validation.ToDictionary());

        var result = await _manager.PlaceOrderAsync(request.ToCommand(), ct);
        return CreatedAtAction(nameof(GetOrder), new { id = result.OrderId }, result.ToResponse());
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<OrderResponse>> GetOrder(Guid id, CancellationToken ct)
    {
        var order = await _manager.GetOrderAsync(new OrderId(id), ct);
        if (order is null)
            return NotFound();

        return Ok(order.ToResponse());
    }
}
```

Validators live in `Host.Api/Validators/` and run before any Manager is called.

---

## Application Layer — Managers

Managers are `internal sealed` classes implementing public contracts. Constructor injection only.

```csharp
internal sealed class OrderWorkflowManager : IOrderWorkflowManager
{
    private readonly IOrderRepository _orders;
    private readonly IPricingEngine _pricing;

    public async Task<PlaceOrderResult> PlaceOrderAsync(PlaceOrderCommand command, CancellationToken ct)
    {
        var price = _pricing.CalculatePrice(command.ToPricingContext());
        var order = Order.Create(command.CustomerId, command.Lines, price);
        await _orders.SaveAsync(order, ct);
        return new PlaceOrderResult(order.Id);
    }
}
```

---

## Domain Layer — Engines and Entities

**Engines**: Stateless, `internal sealed`, implement public contracts.

```csharp
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
```

**Entities**: Enforce invariants, raise domain events.

```csharp
public class Order
{
    private readonly List<IDomainEvent> _events = new();
    public OrderId Id { get; }
    public OrderStatus Status { get; private set; }
    public IReadOnlyList<IDomainEvent> DomainEvents => _events.AsReadOnly();

    public void Confirm()
    {
        Guard.Against.InvalidInput(Status, nameof(Status),
            s => s == OrderStatus.Pending, "Order must be pending to confirm.");
        Status = OrderStatus.Confirmed;
        _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
    }
}
```

**Value Objects**: Immutable records.

```csharp
public record Money(decimal Amount, Currency Currency);
```

---

## Infrastructure Layer — EF Core and Resource Access

All EF Core code lives here. `DbContext` never leaves this project.

**Repository Pattern**:
```csharp
internal sealed class OrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;

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

**EF Core Rules**:
- Use `IEntityTypeConfiguration<T>` per entity — no data annotations on domain models
- Use `OwnsOne` to persist value objects as columns in the parent table
- Prefer LINQ; use raw SQL only with documented performance justification

**Migrations**:
```bash
dotnet ef migrations add <Name> --project YourApp.Infrastructure --startup-project YourApp.Host.Api
dotnet ef database update --project YourApp.Infrastructure --startup-project YourApp.Host.Api
```

Apply in production via CI/CD, not at application startup.

---

## Cross-cutting — Serilog and OpenTelemetry

**Serilog**: Structured logging always.

```csharp
_logger.LogInformation("Order {OrderId} confirmed for customer {CustomerId}", orderId, customerId);
```

**OpenTelemetry**:
```csharp
services.AddOpenTelemetry()
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddOtlpExporter());
```

---

See [references/IMPLEMENTATIONS.md](references/IMPLEMENTATIONS.md) for detailed implementation examples including ASP.NET Core Identity, JWT, HTTP resiliency, and complete configuration samples.
