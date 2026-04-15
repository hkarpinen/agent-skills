# Integration Testing with Testcontainers

PostgreSQL-specific integration test setup. Each test collection shares one container to avoid per-test startup overhead.

```csharp
// Tests/Infrastructure/PostgresFixture.cs
public class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("testdb")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    public AppDbContext DbContext { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        await _container.StartAsync();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_container.GetConnectionString(), npgsql =>
                npgsql.MigrationsAssembly("YourApp.Infrastructure"))
            .UseSnakeCaseNamingConvention()
            .Options;

        DbContext = new AppDbContext(options);
        await DbContext.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        await DbContext.DisposeAsync();
        await _container.DisposeAsync();
    }
}

[CollectionDefinition("Postgres")]
public class PostgresCollection : ICollectionFixture<PostgresFixture> { }

// Tests/Orders/OrderRepositoryTests.cs
[Collection("Postgres")]
public class OrderRepositoryTests
{
    private readonly AppDbContext _db;
    private readonly OrderRepository _sut;

    public OrderRepositoryTests(PostgresFixture fixture)
    {
        _db = fixture.DbContext;
        _sut = new OrderRepository(_db);
    }

    [Fact]
    public async Task SaveAsync_WhenOrderIsNew_PersistsToDatabase()
    {
        var order = OrderBuilder.APendingOrder().Build();

        await _sut.SaveAsync(order);

        var persisted = await _db.Orders.FindAsync(order.Id.Value);
        persisted.Should().NotBeNull();
        persisted!.Status.Should().Be("pending");
    }
}
```
