# Integration Testing with Testcontainers

This file covers the **xUnit-side** patterns for Testcontainers-based integration
tests: container lifecycle, fixture sharing, collection definitions, and validator
tests. Database-provider specifics (Npgsql connection strings, snake_case
configuration, migration commands, schema seeding) belong in the DB bridge skill:

- PostgreSQL + EF Core: see `dotnet-efcore-postgres/references/TESTCONTAINERS.md`
- SQL Server + EF Core: see the corresponding bridge (when available)

---

## Fixture Lifecycle — `IAsyncLifetime`

Containers start slowly (seconds). Share one container per test collection via
xUnit's `IAsyncLifetime`. Never start a container per test — that turns a
30-second suite into a 30-minute one.

```csharp
public class DatabaseFixture : IAsyncLifetime
{
    // Container + DbContext fields owned by the bridge skill — see
    // dotnet-efcore-postgres/references/TESTCONTAINERS.md for the Postgres version.

    public async Task InitializeAsync()
    {
        // 1. Start the container
        // 2. Build DbContext against the container's connection string
        // 3. Apply migrations
    }

    public async Task DisposeAsync()
    {
        // Dispose DbContext, then dispose the container
    }
}
```

Rules:
- One container per *collection*, not per test class and not per test.
- `InitializeAsync` runs once before the first test in the collection.
- `DisposeAsync` runs once after the last test in the collection.
- Do not start containers in a test constructor — the constructor runs per test.

---

## Collection Definition

```csharp
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }

[Collection("Database")]
public class OrderRepositoryTests
{
    private readonly DatabaseFixture _fixture;

    public OrderRepositoryTests(DatabaseFixture fixture) => _fixture = fixture;

    // Tests reuse the shared container via _fixture
}
```

Rules:
- Every test class that needs the database must carry `[Collection("Database")]`.
- xUnit disables parallelism *within* a collection — tests in the same collection
  run serially. This is the correct default for stateful DB tests.
- Classes in *different* collections still run in parallel with each other.

---

## Test Isolation Between Cases

Shared container + parallelism-off does not give per-test isolation — tests still
see each other's writes. Pick one strategy and apply it consistently:

| Strategy | When to use |
|---|---|
| Unique identifiers per test (GUIDs, random suffixes) | Read-mostly tests, cheap |
| Transaction-per-test rollback | Works only when no code-under-test commits internally |
| `Respawn` (truncate between tests) | Large suites, best general-purpose choice |
| Drop + recreate schema per test | Last resort; slow |

Do not mix strategies in the same collection — debugging a suite that sometimes
rolls back and sometimes truncates is a waste of a lifetime.

---

## Validator Tests

FluentValidation validators are unit tests — no container needed. Use
`FluentValidation.TestHelper` for expressive assertions on validation failures.

```csharp
public class PlaceOrderRequestValidatorTests
{
    private readonly PlaceOrderRequestValidator _validator = new();

    [Fact]
    public void WhenLinesIsEmpty_ShouldFailWithExpectedMessage()
    {
        var request = new PlaceOrderRequest { CustomerId = Guid.NewGuid(), Lines = [] };

        var result = _validator.TestValidate(request);

        result.ShouldHaveValidationErrorFor(x => x.Lines)
            .WithErrorMessage("Order must have at least one line.");
    }

    [Fact]
    public void WhenRequestIsValid_ShouldPassValidation()
    {
        var request = PlaceOrderRequestBuilder.AValidRequest().Build();

        var result = _validator.TestValidate(request);

        result.ShouldNotHaveAnyValidationErrors();
    }
}
```

---

## WebApplicationFactory for Client/API Tests

For end-to-end HTTP tests of the `Client` project, use
`Microsoft.AspNetCore.Mvc.Testing`. Override the DB-provider registration inside
`WebApplicationFactory<TEntryPoint>.ConfigureWebHost` to point at the
Testcontainers container from the bridge's fixture.

```csharp
public class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly DatabaseFixture _db = new();

    public Task InitializeAsync() => _db.InitializeAsync();
    public new Task DisposeAsync() => _db.DisposeAsync();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Replace the DbContext registration with one pointed at the test container.
            // Exact replacement syntax is provider-specific — see the bridge skill.
        });
    }
}
```
