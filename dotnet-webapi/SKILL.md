---
name: dotnet-webapi
description: Architecture-agnostic ASP.NET Core Web API stack — package selection, Program.cs wiring, DI primitives, controllers, FluentValidation, EF Core registration, ASP.NET Core Identity + JWT, Serilog, OpenTelemetry, and HttpClient resilience. Use when building or scaffolding a .NET Web API. Does NOT define solution/project structure, layer model, or where orchestrators live — those are owned by an architecture bridge (e.g. `dotnet-idesign`). Does NOT supply the DB provider — compose with a DB bridge (e.g. `dotnet-efcore-postgres`). Does NOT cover containerization — compose with `dotnet-webapi-docker`.
---

## Composability

This skill covers ASP.NET Core framework concerns only — the things that are
true of any .NET Web API regardless of how you organize it internally. It is
deliberately architecture-agnostic:

| Concern | Owned by |
|---|---|
| Solution / project structure, layer names, ServiceExtensions composition chain, DI lifetimes per role | An architecture bridge (e.g. `dotnet-idesign`) |
| Orchestrator/use-case naming conventions (Manager vs UseCase vs Handler vs Service) | An architecture bridge |
| DB provider, DbContext definition, entity configuration, migrations on the provider | A DB bridge (e.g. `dotnet-efcore-postgres`) |
| Containerization | `dotnet-webapi-docker` |
| Test framework tooling | `dotnet-testing` |

Load this skill alongside one architecture bridge and one DB bridge. Swap
either of those without touching this skill.

---

## Core Package Stack

| Concern | Key packages |
|---|---|
| API surface | `Microsoft.AspNetCore.OpenApi`, `Scalar.AspNetCore` (or `Swashbuckle.AspNetCore` for Swagger UI) |
| Request validation | `FluentValidation.AspNetCore`, `FluentValidation.DependencyInjectionExtensions` |
| Data access (core — add a provider via the DB bridge) | `Microsoft.EntityFrameworkCore`, `Microsoft.EntityFrameworkCore.Tools`, `Microsoft.EntityFrameworkCore.Design` |
| Identity / auth | `Microsoft.AspNetCore.Identity.EntityFrameworkCore`, `Microsoft.AspNetCore.Authentication.JwtBearer`, `System.IdentityModel.Tokens.Jwt` |
| Observability | `Serilog.AspNetCore`, `OpenTelemetry.Extensions.Hosting`, `OpenTelemetry.Instrumentation.AspNetCore`, `OpenTelemetry.Instrumentation.Http`, `OpenTelemetry.Instrumentation.EntityFrameworkCore`, `OpenTelemetry.Exporter.OpenTelemetryProtocol` |
| Health checks | `AspNetCore.HealthChecks.NpgSql` (or the DB-appropriate package) |
| Outbound HTTP resilience | `Microsoft.Extensions.Http.Resilience` |

The architecture bridge decides which of these packages belong in which
project. See [references/PACKAGES.md](references/PACKAGES.md) for the full list
organized by concern.

---

## DI Primitive — `ServiceExtensions` per Library

Every class library exposes exactly one `IServiceCollection` extension method.
The executable (host) project calls each; no library registers services from
another library.

```csharp
public static class PaymentsServiceExtensions
{
    public static IServiceCollection AddPayments(this IServiceCollection services)
    {
        services.AddScoped<IPaymentGateway, StripePaymentGateway>();
        return services;
    }
}
```

This is the *pattern*. The architecture bridge defines the **names and
composition order** of the `.AddFoo()` chain called in `Program.cs`.

**Lifetime defaults** (override only with a clear reason):
- `Scoped` — anything bound to a request / unit of work (handlers, repositories, `DbContext`)
- `Singleton` — stateless cross-cutting services (loggers, clock, config options)
- `Transient` — lightweight value-like services (e.g. factories)

Never inject a `Scoped` dependency into a `Singleton`. Inject
`IServiceScopeFactory` instead.

---

## Program.cs Shape

```csharp
var builder = WebApplication.CreateBuilder(args);

// Logging — configure before anything else so startup errors get captured
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .CreateBootstrapLogger();

builder.Host.UseSerilog((ctx, services, config) => config
    .ReadFrom.Configuration(ctx.Configuration)
    .ReadFrom.Services(services));

// Composition — architecture bridge supplies the .AddFoo() chain
builder.Services
    .AddControllers();

builder.Services
    .AddEndpointsApiExplorer()
    .AddSwaggerGen()
    .AddFluentValidationAutoValidation()
    .AddValidatorsFromAssemblyContaining<Program>();

var app = builder.Build();

app.UseExceptionHandler();
app.UseSerilogRequestLogging();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.Run();
```

Rules:
- Middleware order is significant and non-obvious. Keep it:
  exception-handler → request-logging → auth-n → auth-z → endpoints.
- Do not apply EF Core migrations from `Program.cs` — the DB bridge and
  `dotnet-webapi-docker` specify the correct migration strategy.

---

## Controllers

- One controller per resource cluster (`OrdersController`, `CustomersController`).
- `[ApiController]` for automatic model-state validation.
- Return `ActionResult<T>` for typed responses.
- Validate the request → call the orchestrator → return the mapped result.
  Controllers contain no business logic.

```csharp
[ApiController]
[Route("api/orders")]
[Authorize]
public class OrdersController : ControllerBase
{
    // IPlaceOrderHandler is a placeholder for whatever orchestrator type your
    // architecture bridge defines (Manager, UseCase, CommandHandler, etc.).
    private readonly IPlaceOrderHandler _placeOrder;
    private readonly IValidator<PlaceOrderRequest> _validator;

    public OrdersController(IPlaceOrderHandler placeOrder, IValidator<PlaceOrderRequest> validator)
    {
        _placeOrder = placeOrder;
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

        var result = await _placeOrder.HandleAsync(request.ToCommand(), ct);
        return CreatedAtAction(nameof(GetOrder), new { id = result.OrderId }, result.ToResponse());
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<OrderResponse>> GetOrder(Guid id, CancellationToken ct)
    {
        var order = await _placeOrder.GetAsync(id, ct);
        return order is null ? NotFound() : Ok(order.ToResponse());
    }
}
```

Request/response DTOs and mapping extensions live alongside the controllers.
Where validators physically live (which project) is an architecture-bridge
decision.

---

## FluentValidation

One validator per request DTO. Register with
`.AddValidatorsFromAssemblyContaining<T>()` — one call per assembly that ships
validators.

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

---

## EF Core Registration

This skill covers only the *framework-level* registration. The DbContext
itself, entity configurations, provider selection, connection-string
conventions, and migration policy are owned by the DB bridge.

```csharp
// Called by whichever project the architecture bridge assigns as DbContext owner.
services.AddDbContext<AppDbContext>(dbOptions);
```

`dbOptions` is an `Action<DbContextOptionsBuilder>` supplied by the DB bridge
(e.g. `dotnet-efcore-postgres` configures Npgsql + `UseSnakeCaseNamingConvention`).

---

## ASP.NET Core Identity + JWT

Identity + JWT is an ASP.NET Core concern and stays in this skill. The
`AppDbContext` type name is used below as a placeholder — the DB bridge owns
its definition.

```csharp
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
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwt.Issuer,
        ValidAudience = jwt.Audience,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Secret)),
        ClockSkew = TimeSpan.Zero
    };
});
```

### Identity + DDD Reconciliation

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

---

## Serilog — Structured Logging Only

Never interpolate values into log messages. Always use message templates so the
values are captured as structured properties.

```csharp
_logger.LogInformation(
    "Order {OrderId} confirmed for customer {CustomerId}",
    orderId, customerId);
```

Minimum sink set: console + file. Add environment/thread enrichers. Override
`Microsoft.EntityFrameworkCore` to `Warning` unless actively debugging SQL.

---

## OpenTelemetry

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

Configure the exporter via environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT`,
`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`) — never hard-code the endpoint.

---

## HTTP Resilience

All outbound `HttpClient` calls use named/typed clients with the standard
resilience handler (retries, circuit breaker, timeout).

```csharp
services.AddHttpClient<IPaymentGateway, StripePaymentGateway>(client =>
    client.BaseAddress = new Uri(configuration["Stripe:BaseUrl"]!))
    .AddStandardResilienceHandler();
```

Rules:
- Never new up an `HttpClient` manually — it defeats socket reuse and resilience.
- The interface that the typed client implements is an architecture-bridge
  concern (it lives in Domain in IDesign; elsewhere in other architectures).

---

## Pagination

Use cursor-based (keyset) pagination for list endpoints. Offset-based pagination
degrades as offset grows and produces inconsistent results when data changes
between pages.

### Request/Response Shape

```csharp
// Request
public record PagedRequest(Guid? Cursor, int Limit = 20);

// Response
public record PagedResponse<T>(IReadOnlyList<T> Items, Guid? NextCursor);
```

Controller pattern:

```csharp
[HttpGet]
public async Task<ActionResult<PagedResponse<OrderResponse>>> List(
    [FromQuery] Guid? cursor,
    [FromQuery] int limit = 20,
    CancellationToken ct = default)
{
    limit = Math.Clamp(limit, 1, 100);
    var result = await _query.ListAsync(cursor, limit, ct);
    return Ok(result);
}
```

Rules:
- Clamp `limit` to a server-defined maximum (e.g. 100). Never allow unbounded page sizes.
- Return `NextCursor` as `null` when there are no more pages.
- The cursor is an opaque value to the client — do not document its internal structure.
- The query layer (owned by architecture bridge) translates the cursor to a `WHERE id > @cursor` clause.

---

## Policy-Based Authorization

Use ASP.NET Core's policy-based authorization for role and claim checks. Avoid
inline role strings on every endpoint.

### Define Policies

```csharp
services.AddAuthorization(options =>
{
    options.AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"));
    options.AddPolicy("ModeratorOrAdmin", policy =>
        policy.RequireRole("Admin", "Moderator"));
});
```

### Apply to Controllers or Endpoints

```csharp
[Authorize(Policy = "AdminOnly")]
[HttpDelete("{id:guid}")]
public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
{
    await _handler.DeleteAsync(id, ct);
    return NoContent();
}
```

Rules:
- Define all policies in a single registration block, close to the Identity registration.
- Prefer `[Authorize(Policy = "...")]` over `[Authorize(Roles = "...")]`. Policies are
  testable and composable; raw role strings are scattered and fragile.
- For resource-based authorization (e.g. "user can only edit their own posts"), implement
  `IAuthorizationHandler` with a custom requirement.
- The architecture bridge decides where the policy registration physically lives (which `ServiceExtensions`).

---

See [references/PACKAGES.md](references/PACKAGES.md) for the full package list
and [references/IMPLEMENTATIONS.md](references/IMPLEMENTATIONS.md) for extended
examples (AppUser, JWT token service, refresh tokens, full Program.cs, Serilog config, OTel
config).

---

## CORS

When a frontend application makes browser-side API calls (e.g., from a Client Component or SPA), CORS headers are required. Server-side fetches (e.g., from Next.js Server Components) bypass CORS entirely.

```csharp
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy
            .WithOrigins(builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()!)
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();   // required if using HTTP-only cookies for auth
    });
});
```

Apply the policy in middleware — before `UseAuthentication`:

```csharp
app.UseCors("AllowFrontend");
app.UseAuthentication();
app.UseAuthorization();
```

Rules:
- Never use `.AllowAnyOrigin()` with `.AllowCredentials()` — this is forbidden by the CORS spec and will produce a browser error.
- Configure allowed origins from `appsettings.json` or environment variables, not hard-coded strings.
- When behind a reverse proxy, the browser's `Origin` header contains the proxy's URL (e.g., `http://localhost`), not the backend's internal URL. Configure accordingly.
- In development, allow `http://localhost:3000` (Next.js dev server). In production, allow only the proxy's public URL.
- Server-to-server calls (Next.js Server Components, Server Actions) do not send `Origin` headers and are not affected by CORS.

---

## Health Checks

Expose a health check endpoint for Docker Compose healthchecks, load balancers, and orchestrators.

```csharp
// Registration
builder.Services
    .AddHealthChecks()
    .AddNpgSql(builder.Configuration.GetConnectionString("Default")!);  // DB-specific; swap for your provider

// Endpoint mapping (after MapControllers)
app.MapHealthChecks("/healthz");
```

Rules:
- The health check endpoint must be unauthenticated — Docker and load balancers cannot pass JWTs.
- Add a database check so the health endpoint verifies connectivity, not just that the process is running.
- The DB bridge skill specifies which health check package to use for the database provider.
- Use `/healthz` as the path consistently across all services. Reference this path in Compose `healthcheck` and load balancer configuration.

Docker Compose integration:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8080/healthz || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 3
```
