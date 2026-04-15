# Integration Testing with Testcontainers

## Shared Fixture Setup

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
            .UseNpgsql(_container.GetConnectionString())
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
```

## Repository Tests

```csharp
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
        // Arrange
        var order = OrderBuilder.APendingOrder().Build();

        // Act
        await _sut.SaveAsync(order);

        // Assert
        var persisted = await _db.Orders.FindAsync(order.Id.Value);
        persisted.Should().NotBeNull();
        persisted!.Status.Should().Be("pending");
    }

    [Fact]
    public async Task GetAsync_WhenOrderExists_ReturnsMappedDomainOrder()
    {
        // Arrange — seed via DbContext directly
        var entity = OrderEntityBuilder.AnOrderEntity().Build();
        _db.Orders.Add(entity);
        await _db.SaveChangesAsync();

        // Act
        var result = await _sut.GetAsync(new OrderId(entity.Id));

        // Assert
        result.Should().NotBeNull();
        result!.Id.Value.Should().Be(entity.Id);
    }
}
```

## SQL Server Container

```csharp
public class DatabaseFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder()
        .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
        .Build();

    public AppDbContext DbContext { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        await _container.StartAsync();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_container.GetConnectionString())
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
```

## Validator Tests

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
