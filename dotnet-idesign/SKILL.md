---
name: dotnet-idesign
description: Bridge between the IDesign Method and .NET — how IDesign's Client/Application/Domain/Infrastructure layer model maps to a .NET solution. Use when laying out a .NET solution under IDesign, organizing csproj dependencies to enforce call direction, choosing DI lifetimes per layer role, or writing Managers, Engines, and Resource Access components in C#.
---

## Scope

This skill owns the **.NET realization of IDesign**. It specifies:

- Solution and project structure
- Project reference graph (how csproj dependencies enforce IDesign call direction)
- `ServiceExtensions` naming and composition chain
- DI lifetimes per layer role
- Manager / Engine / Resource Access conventions in C#
- Migration CLI invocations that target IDesign projects

---

## Project Structure

Each IDesign layer is a separate class library named after the layer itself — no
solution prefix. The `Client` project is the only executable and is the
composition root. All tests live in a single `Tests` project.

```
YourApp.sln
├── src/
│   ├── Client/           ← Client layer (executable — host, controllers, composition root)
│   ├── Application/      ← Application layer (Managers)
│   ├── Domain/           ← Domain layer (Engines, entities, value objects, repository interfaces)
│   ├── Infrastructure/   ← Infrastructure layer (Resource Access — data access, gateways)
│   └── Utilities/        ← Cross-cutting (logging, config)
└── tests/
    └── Tests/            ← single test project covering all layers and test types
```

Assembly names are the bare layer noun (`Client.dll`, `Domain.dll`, etc.).

---

## Project Reference Graph

The csproj graph is how IDesign's call-direction rule is **compiler-enforced**.

```
Client         → Application, Domain, Infrastructure, Utilities
Application    → Domain, Utilities
Domain         → Utilities
Infrastructure → Domain, Utilities
Utilities      → (nothing)
Tests          → Client, Application, Domain, Infrastructure, Utilities
```

Rules:
- `Application` references `Domain` (it calls Engines and loads aggregates), but
  **never** references `Infrastructure` as a compile-time dependency. It
  depends on Infrastructure via repository *interfaces* defined in `Domain`.
- `Domain` references nothing except `Utilities`. An attempt to add a reference
  from `Domain` to `Infrastructure` is an architectural defect and will
  compile-break other layers intentionally.
- Only `Client` composes all layers — it is the only place that wires
  interfaces to implementations.

---

## ServiceExtensions per Library

Every library exposes **exactly one** `IServiceCollection` extension method,
named `Add<LayerName>`. The host calls each; no library registers services from
any other library.

```csharp
// Domain/DomainServiceExtensions.cs
public static class DomainServiceExtensions
{
    public static IServiceCollection AddDomain(this IServiceCollection services)
    {
        services.AddScoped<IPricingEngine, TieredPricingEngine>();
        services.AddScoped<IFraudDetectionEngine, FraudDetectionEngine>();
        return services;
    }
}
```

The `Client` project composes the whole graph in a fixed order:

```csharp
// Client/Program.cs
builder.Services
    .AddUtilities()
    .AddDomain()
    .AddApplication()
    .AddInfrastructure(builder.Configuration)
    .AddClient();   // controllers, validators, Swagger — ASP.NET Core plumbing
```

The data-access provider registration (e.g. EF Core + Npgsql) belongs inside
`AddInfrastructure`.

Rules:
- Order matters: register Utilities first (no dependencies), Infrastructure last
  (depends on everything). Rearranging the chain hides registration bugs.
- No library `Add*` method references types from a sibling library. If
  `AddApplication` registered an `OrderRepository`, it would couple Application
  to Infrastructure — forbidden.

---

## DI Lifetimes per Layer Role

| Role | Lifetime | Rationale |
|---|---|---|
| Manager (Application) | `Scoped` | Bound to the request / unit of work |
| Engine (Domain) | `Scoped` | Pure logic; `Scoped` keeps disposal behaviour uniform with Managers and Repositories |
| Repository / Gateway (Infrastructure) | `Scoped` | Holds a data-access context or connection; lifecycle-matched to the request |
| Utility (cross-cutting) | `Singleton` | Stateless (logger, clock, config); one instance per process |
| Framework primitives (`IValidator<T>`, `IOptions<T>`, etc.) | Framework default | Do not override |

Rules:
- Never resolve a `Scoped` dependency inside a `Singleton`. Inject an
  `IServiceScopeFactory` instead.
- Engines are stateless, but register them as `Scoped` anyway — making
  lifetimes uniform across layers makes composition auditable.

---

## Application Layer — Managers

Managers are `internal sealed` classes implementing a public contract in their
own library. Constructor injection only.

```csharp
// Application/IOrderWorkflowManager.cs  (public contract)
public interface IOrderWorkflowManager
{
    Task<PlaceOrderResult> PlaceOrderAsync(PlaceOrderCommand command, CancellationToken ct);
}

// Application/OrderWorkflowManager.cs  (internal sealed)
internal sealed class OrderWorkflowManager : IOrderWorkflowManager
{
    private readonly IOrderRepository _orders;
    private readonly IPricingEngine _pricing;

    public OrderWorkflowManager(IOrderRepository orders, IPricingEngine pricing)
    {
        _orders = orders;
        _pricing = pricing;
    }

    public async Task<PlaceOrderResult> PlaceOrderAsync(
        PlaceOrderCommand command,
        CancellationToken ct)
    {
        var price = _pricing.CalculatePrice(command.ToPricingContext());
        var order = Order.Create(command.CustomerId, command.Lines, price);
        await _orders.SaveAsync(order, ct);
        return new PlaceOrderResult(order.Id);
    }
}
```

Rules:
- Managers orchestrate — no business rules. Rules live in Engines or aggregates.
- Managers do not call other Managers. Cross-use-case composition belongs in
  the Client or in a new Manager.
- `internal sealed` + registered via the library's `AddApplication` keeps the
  implementation hidden from the Client.

---

## Domain Layer — Engines

Engines are `internal sealed`, stateless, implement a public contract. No I/O.

```csharp
// Domain/IPricingEngine.cs  (public contract)
public interface IPricingEngine
{
    Money CalculatePrice(PricingContext context);
}

// Domain/TieredPricingEngine.cs  (internal sealed)
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

Rules:
- No `HttpClient`, no data-access context, no file I/O, no `DateTime.UtcNow` (inject a
  clock via `Utilities`).
- Engines do not call other Engines through DI — if composition is needed, the
  caller is a Manager.
- Entity / value-object patterns (invariants, domain events) are modelling
  concerns.

---

## Infrastructure Layer — Resource Access

Repository *interfaces* live in `Domain`; implementations live in
`Infrastructure` as `internal sealed`. The data-access context never leaves
`Infrastructure`.

```csharp
// Domain/IOrderRepository.cs  (part of the domain contract)
public interface IOrderRepository
{
    Task<Order?> GetAsync(OrderId id, CancellationToken ct = default);
    Task SaveAsync(Order order, CancellationToken ct = default);
}

// Infrastructure/OrderRepository.cs  (internal sealed)
// The data-access context type and wiring are Infrastructure concerns.
// This skill specifies WHERE implementations live.
internal sealed class OrderRepository : IOrderRepository
{
    // Constructor receives the data-access context registered by the DB bridge

    public async Task<Order?> GetAsync(OrderId id, CancellationToken ct = default)
        => /* load and map to domain object */;

    public async Task SaveAsync(Order order, CancellationToken ct = default)
        => /* map to persistence and save */;
}
```

The data-access context, entity configurations, and provider registration are
Infrastructure concerns. This skill specifies *where* Repository
implementations live.

---

## Migrations — CLI Invocations

The `Infrastructure` project owns the data-access context, so migrations go
there; the `Client` project is the startup project.

```bash
# Example using EF Core CLI (adapt for your data-access tool)
dotnet ef migrations add <Name> \
  --project src/Infrastructure \
  --startup-project src/Client

dotnet ef database update \
  --project src/Infrastructure \
  --startup-project src/Client
```

Ensure migrations target the `Infrastructure` assembly:

```csharp
// The DB bridge supplies the provider-specific options.
// Ensure the migrations assembly targets Infrastructure:
options.MigrationsAssembly("Infrastructure")
```

---

## Test Project Organization

A single `Tests` project references every production project. General test
strategy (single project, folder-per-test-type) and xUnit setup are separate
concerns. This section specifies only the IDesign-specific wiring.

```bash
# Reference every IDesign layer
dotnet add tests/Tests reference src/Domain/Domain.csproj
dotnet add tests/Tests reference src/Application/Application.csproj
dotnet add tests/Tests reference src/Infrastructure/Infrastructure.csproj
dotnet add tests/Tests reference src/Client/Client.csproj
dotnet add tests/Tests reference src/Utilities/Utilities.csproj
```

Folder names mirror IDesign layers:

```
tests/
└── Tests/
    ├── Unit/
    │   ├── Domain/              ← Engine, entity, value-object tests
    │   └── Application/         ← Manager tests with mocked Infrastructure
    ├── Integration/
    │   ├── Infrastructure/      ← Repository tests against Testcontainers
    │   └── Client/              ← WebApplicationFactory HTTP tests
    └── EndToEnd/
```

Run a subset via test-runner filter:

```bash
dotnet test --filter "FullyQualifiedName~.Unit."
dotnet test --filter "FullyQualifiedName~.Integration."
```

---

## ASP.NET Core Identity + DDD Reconciliation

When using ASP.NET Core Identity alongside DDD patterns (e.g., in an Identity bounded context modeled with aggregates), tension arises: Identity owns the user table schema (`AspNetUsers`, `AspNetRoles`), while DDD expects the domain model to own the schema.

**Recommended approach — Extend `IdentityUser`:**

```csharp
// Domain layer — AppUser extends IdentityUser to add domain fields
public class AppUser : IdentityUser
{
    public string DisplayName { get; private set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset? DeletedAt { get; private set; }

    // Domain behavior lives here
    public void UpdateProfile(string displayName)
    {
        DisplayName = displayName;
    }
}
```

Rules:
- `AppUser` lives in the Domain layer. It extends `IdentityUser` to add domain-specific properties and behavior.
- ASP.NET Core Identity's `UserManager<AppUser>` handles password hashing, lockout, email confirmation, and token generation. Do not reimplement these — they are infrastructure concerns that Identity handles correctly.
- Domain events can still be raised from `AppUser` methods. The Manager collects and dispatches them after `UserManager` persists.
- The `DbContext` inherits from `IdentityDbContext<AppUser>` instead of plain `DbContext`. Entity configurations can coexist with Identity's tables.
- Do **not** create a parallel `User` aggregate that duplicates Identity's data. The `AppUser` extending `IdentityUser` **is** the aggregate root for the Identity context.
- Identity + JWT registration is an ASP.NET Core concern. This section owns where `AppUser` lives in the IDesign layer model and how it reconciles with DDD aggregate patterns.


