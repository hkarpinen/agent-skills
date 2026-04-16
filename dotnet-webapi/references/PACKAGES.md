# Complete Package List

Organized by **concern**, not by project. Which project each package lands in
is an architecture decision — see the architecture bridge you loaded (e.g.
`dotnet-idesign`).

## API Surface

| Package | Purpose |
|---|---|
| `Swashbuckle.AspNetCore` | Swagger UI and OpenAPI spec |
| `Microsoft.AspNetCore.OpenApi` | OpenAPI metadata for Minimal APIs |

## Request Validation

| Package | Purpose |
|---|---|
| `FluentValidation` | Core validation library |
| `FluentValidation.AspNetCore` | ASP.NET Core integration |
| `FluentValidation.DependencyInjectionExtensions` | `AddValidatorsFromAssembly*` helpers |

## Data Access — EF Core (core packages only)

| Package | Purpose |
|---|---|
| `Microsoft.EntityFrameworkCore` | Core EF |
| `Microsoft.EntityFrameworkCore.Tools` | Migrations CLI (`dotnet ef`) |
| `Microsoft.EntityFrameworkCore.Design` | Design-time tooling |

> The **DB provider package** (e.g. `Npgsql.EntityFrameworkCore.PostgreSQL`,
> `Microsoft.EntityFrameworkCore.SqlServer`) is supplied by the DB bridge skill.
> Do not add a provider package here.

## Identity and Authentication

| Package | Purpose |
|---|---|
| `Microsoft.AspNetCore.Identity.EntityFrameworkCore` | Identity with EF Core persistence |
| `Microsoft.AspNetCore.Authentication.JwtBearer` | JWT bearer token validation |
| `System.IdentityModel.Tokens.Jwt` | JWT token generation |

## HTTP Resilience (outbound clients)

| Package | Purpose |
|---|---|
| `Microsoft.Extensions.Http.Resilience` | Polly v8 wrapper for `HttpClient` |

## Observability

| Package | Purpose |
|---|---|
| `Serilog.AspNetCore` | Serilog host integration |
| `Serilog.Sinks.Console` | Console sink |
| `Serilog.Sinks.File` | File sink |
| `Serilog.Enrichers.Environment` | Environment / machine-name enrichment |
| `Serilog.Enrichers.Thread` | Thread ID enrichment |
| `OpenTelemetry.Extensions.Hosting` | OTel hosting integration |
| `OpenTelemetry.Instrumentation.AspNetCore` | HTTP request tracing |
| `OpenTelemetry.Instrumentation.Http` | Outbound HTTP tracing |
| `OpenTelemetry.Instrumentation.EntityFrameworkCore` | EF Core query tracing |
| `OpenTelemetry.Instrumentation.Runtime` | .NET runtime metrics |
| `OpenTelemetry.Exporter.OpenTelemetryProtocol` | OTLP exporter |

## Domain Guard Helpers

| Package | Purpose |
|---|---|
| `Ardalis.GuardClauses` | Guard-clause helpers for invariant enforcement |

## Testing

| Package | Purpose |
|---|---|
| `xunit` + `xunit.runner.visualstudio` | Test framework |
| `Moq` | Mocking |
| `FluentAssertions` | Assertion library |
| `FluentValidation.TestHelper` | Validator unit testing |
| `Testcontainers.*` (e.g. `Testcontainers.PostgreSql`) | Real DB in Docker (provider supplied by DB bridge) |
| `coverlet.collector` | Code coverage collection |
| `Microsoft.AspNetCore.Mvc.Testing` | `WebApplicationFactory` for HTTP tests |
