---
name: dotnet-webapi
description: Architecture-agnostic ASP.NET Core Web API stack — package selection, Program.cs wiring, DI primitives, controllers, FluentValidation, EF Core registration, ASP.NET Core Identity + JWT, Serilog, OpenTelemetry, HttpClient resilience, rate limiting, and health checks. Use when building or scaffolding a .NET Web API. Does NOT define solution/project structure, layer model, or where orchestrators live. Does NOT supply the DB provider. Does NOT cover containerization.
---

---

## Core Package Stack

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
app.UseCors("AllowFrontend");      // CORS before rate limiter and auth
app.UseRateLimiter();              // rate limiter before auth
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/healthz");
app.Run();
```

Rules:
- Middleware order is significant and non-obvious. The canonical order is:
  exception-handler → request-logging → CORS → rate-limiter → auth-n → auth-z → endpoints → health checks.
- Do not apply EF Core migrations from `Program.cs`. Apply migrations via CI/CD scripts or a one-shot container.

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

`dbOptions` is an `Action<DbContextOptionsBuilder>` supplied by the data-access
provider configuration (e.g. Npgsql + `UseSnakeCaseNamingConvention` for PostgreSQL).

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

Use cursor-based (keyset) pagination for list endpoints. This section covers the ASP.NET Core request/response shape.

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
- The query layer (owned by architecture bridge) translates the cursor to a `WHERE` clause.

---

## Authorization

This skill owns only the middleware registration order — see **Program.cs Shape**
above: `app.UseAuthentication()` then `app.UseAuthorization()`.

Authorization policy definitions, `[Authorize]` attribute patterns, resource-based
authorization handlers, and claims mapping are separate concerns from the API framework.

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

Apply the policy in middleware — see the canonical order in **Program.cs Shape** above (`app.UseCors("AllowFrontend")` before rate limiter and auth).

Rules:
- Never use `.AllowAnyOrigin()` with `.AllowCredentials()` — this is forbidden by the CORS spec and will produce a browser error.
- Configure allowed origins from `appsettings.json` or environment variables, not hard-coded strings.
- When behind a reverse proxy, the browser's `Origin` header contains the proxy's URL (e.g., `http://localhost`), not the backend's internal URL. Configure accordingly.
- In development, allow `http://localhost:3000` (Next.js dev server). In production, allow only the proxy's public URL.
- Server-to-server calls (Next.js Server Components, Server Actions) do not send `Origin` headers and are not affected by CORS.

---

## Rate Limiting

Use ASP.NET Core's built-in rate limiter middleware to protect public endpoints from abuse (spam registration, vote flooding, rapid-fire post creation).

### Registration

```csharp
builder.Services.AddRateLimiter(options =>
{
    // Global fallback — applies to all endpoints without a specific policy
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    // Fixed window — e.g., 100 requests per minute per user
    options.AddFixedWindowLimiter("standard", opt =>
    {
        opt.PermitLimit = 100;
        opt.Window = TimeSpan.FromMinutes(1);
        opt.QueueLimit = 0;
    });

    // Strict — for mutation endpoints (post creation, voting)
    options.AddFixedWindowLimiter("strict", opt =>
    {
        opt.PermitLimit = 10;
        opt.Window = TimeSpan.FromMinutes(1);
        opt.QueueLimit = 0;
    });

    // Auth endpoints — prevent brute force
    options.AddSlidingWindowLimiter("auth", opt =>
    {
        opt.PermitLimit = 5;
        opt.Window = TimeSpan.FromMinutes(5);
        opt.SegmentsPerWindow = 5;
        opt.QueueLimit = 0;
    });
});
```

Middleware placement — see the canonical order in **Program.cs Shape** above (`app.UseRateLimiter()` after CORS, before auth).

### Applying to Endpoints

```csharp
[EnableRateLimiting("strict")]
[HttpPost]
public async Task<ActionResult<ThreadResponse>> CreateThread(...)

[EnableRateLimiting("auth")]
[HttpPost("login")]
public async Task<ActionResult<AuthResponse>> Login(...)
```

### Partitioning by User

By default, rate limits apply globally. To partition by authenticated user (or by IP for anonymous users):

```csharp
options.AddFixedWindowLimiter("strict", opt =>
{
    opt.PermitLimit = 10;
    opt.Window = TimeSpan.FromMinutes(1);
    opt.QueueLimit = 0;
});

// Override the partition key globally
options.OnRejected = async (context, ct) =>
{
    context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
    await context.HttpContext.Response.WriteAsync("Too many requests. Try again later.", ct);
};
```

For per-user partitioning, use `AddPolicy` with a custom `IRateLimiterPolicy<string>`:

```csharp
options.AddPolicy("per-user-strict", httpContext =>
{
    var userId = httpContext.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "anonymous";
    return RateLimitPartition.GetFixedWindowLimiter(userId, _ => new FixedWindowRateLimiterOptions
    {
        PermitLimit = 10,
        Window = TimeSpan.FromMinutes(1)
    });
});
```

Rules:
- Always set `RejectionStatusCode` to `429`. The default is `503`, which is misleading.
- Partition by authenticated user ID when available, IP address as fallback. Global (unpartitioned) limits protect only against total throughput overload, not per-user abuse.
- Use `FixedWindowLimiter` for most endpoints. Use `SlidingWindowLimiter` for auth endpoints where burst tolerance matters.
- Place rate limiter middleware **after** CORS and **before** authentication. Rate-limited requests should be rejected before doing auth work.
- Do not rate-limit health check endpoints — they are called by infrastructure, not users.
- Configure limits via `appsettings.json` or environment variables in production — do not hard-code.

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
- Add a database check so the health endpoint verifies connectivity, not just that the process is running. Use the health check package appropriate for your database provider.
- Use `/healthz` as the path consistently across all services. Reference this path in Compose `healthcheck` and load balancer configuration.

Docker Compose integration:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8080/healthz || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 3
```
