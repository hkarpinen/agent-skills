# Complete Package List

## Client (YourApp.Host.Api)

| Package | Purpose |
|---|---|
| `Swashbuckle.AspNetCore` | Swagger UI and OpenAPI spec |
| `Microsoft.AspNetCore.OpenApi` | OpenAPI metadata for Minimal APIs |
| `FluentValidation.AspNetCore` | Validator registration and DI integration |

## Application (YourApp.Application)

No additional packages. Managers are pure orchestration.

## Domain (YourApp.Domain)

| Package | Purpose |
|---|---|
| `Ardalis.GuardClauses` | Guard clause helpers for invariant enforcement |

## Infrastructure (YourApp.Infrastructure)

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

## Cross-cutting (YourApp.Utilities)

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

## Test Projects

| Package | Purpose |
|---|---|
| `xunit` + `xunit.runner.visualstudio` | Test framework |
| `Moq` | Mocking |
| `FluentAssertions` | Assertion library |
| `FluentValidation.TestHelper` | Validator unit testing |
| `Testcontainers.MsSql` / `Testcontainers.PostgreSql` | Real DB in Docker |
| `coverlet.collector` | Code coverage collection |
| `Microsoft.AspNetCore.Mvc.Testing` | WebApplicationFactory for Host tests |
