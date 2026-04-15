# dotnet-testing

> xUnit, Moq, FluentAssertions, Testcontainers — testing conventions and coverage rules for .NET projects.

**When to use this skill**: writing or generating tests, setting up test projects, asking about coverage, mocking, assertions, Testcontainers, FluentAssertions, or test structure in a .NET project.

**Composes with**: `righting-software` (which layer to test how — always load for any test generation task), `dotnet-webapi` (the production stack being tested).

---

Coverage Requirements (Non-Negotiable)

| Scope | Minimum coverage |
|---|---|
| Domain (entities, value objects, aggregates, domain events) | **100%** |
| Engines | **90%** |
| Managers | **80%** |
| Resource Access | **80%** (integration tests count) |
| API endpoints / validators | **80%** |
| Utilities | **80%** |
| **Overall project minimum** | **80%** |

When generating production code, always generate accompanying tests. Coverage targets
must be met by the generated test suite, not deferred.

---

## Test Stack

| Purpose | Package |
|---|---|
| Test framework | `xunit` + `xunit.runner.visualstudio` |
| Mocking | `Moq` |
| Assertions | `FluentAssertions` |
| Validator testing | `FluentValidation.TestHelper` |
| Integration DB | `Testcontainers.MsSql` |
| Coverage collection | `coverlet.collector` |
| Coverage reporting | `coverlet.msbuild` (for CLI reports) |

---

## Project Structure

One test project per production library project. Never mix unit and integration tests
in the same project — they have different infrastructure requirements and run characteristics.

```
tests/
├── YourApp.Domain.Tests/             ← Unit tests — 100% coverage required
├── YourApp.Engines.Tests/            ← Unit tests — 90% coverage required
├── YourApp.Managers.Tests/           ← Integration tests (ResourceAccess mocked via Moq)
├── YourApp.ResourceAccess.Tests/     ← Integration tests (Testcontainers real DB)
└── YourApp.Host.Api.Tests/           ← Endpoint + validator tests (WebApplicationFactory)
```

Each test project references only the production project it tests plus the test stack
packages. Test projects never reference each other.

---

## Naming Convention

```
[MethodUnderTest]_[Scenario]_[ExpectedResult]

Examples:
  Confirm_WhenOrderIsPending_RaisesOrderConfirmedEvent
  CalculatePrice_WhenCustomerIsGoldTier_AppliesDiscount
  GetAsync_WhenOrderDoesNotExist_ReturnsNull
  PlaceOrderValidator_WhenLinesIsEmpty_FailsValidation
```

---

## Unit Test Pattern (Domain & Engines)

```csharp
public class OrderTests
{
    [Fact]
    public void Confirm_WhenOrderIsPending_SetsStatusToConfirmedAndRaisesEvent()
    {
        // Arrange
        var order = OrderBuilder.APendingOrder().Build();

        // Act
        order.Confirm();

        // Assert
        order.Status.Should().Be(OrderStatus.Confirmed);
        order.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<OrderConfirmed>()
            .Which.OrderId.Should().Be(order.Id);
    }

    [Fact]
    public void Confirm_WhenOrderIsAlreadyConfirmed_ThrowsInvalidOperationException()
    {
        // Arrange
        var order = OrderBuilder.AConfirmedOrder().Build();

        // Act
        var act = () => order.Confirm();

        // Assert
        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*pending*");
    }
}
```

---

## Moq — Mocking Rules

- Mock only interfaces, never concrete classes.
- Use `Mock<T>` for dependencies that must be isolated.
- Use `It.IsAny<T>()` sparingly — prefer specific argument matchers to catch regressions.
- Verify calls on mocks only when the call itself is the behavior under test.
- Never mock the domain model — test it directly.
- Never mock `DbContext` — use Testcontainers for Resource Access tests.

```csharp
public class OrderWorkflowManagerTests
{
    private readonly Mock<IOrderRepository> _repositoryMock = new();
    private readonly Mock<IPricingEngine> _pricingEngineMock = new();
    private readonly OrderWorkflowManager _sut;

    public OrderWorkflowManagerTests()
    {
        _sut = new OrderWorkflowManager(_repositoryMock.Object, _pricingEngineMock.Object);
    }

    [Fact]
    public async Task PlaceOrderAsync_WhenValid_SavesOrderAndReturnsId()
    {
        // Arrange
        var command = PlaceOrderCommandBuilder.AValidCommand().Build();
        _pricingEngineMock
            .Setup(e => e.CalculatePrice(It.Is<PricingContext>(c => c.CustomerId == command.CustomerId)))
            .Returns(Money.Of(100, Currency.USD));

        // Act
        var result = await _sut.PlaceOrderAsync(command);

        // Assert
        result.Should().NotBeNull();
        _repositoryMock.Verify(r => r.SaveAsync(It.Is<Order>(o => o.CustomerId == command.CustomerId), default), Times.Once);
    }
}
```

---

## FluentAssertions — Key Patterns

```csharp
// Primitives
result.Should().Be(expected);
result.Should().NotBeNull();
result.Should().BeGreaterThan(0);

// Strings
message.Should().Contain("pending");
message.Should().StartWith("Order");

// Collections
items.Should().HaveCount(3);
items.Should().ContainSingle();
items.Should().BeEquivalentTo(expected);
items.Should().AllSatisfy(i => i.Status.Should().Be(OrderStatus.Active));

// Exceptions
act.Should().Throw<InvalidOperationException>().WithMessage("*pending*");
await act.Should().ThrowAsync<NotFoundException>();

// Domain events
order.DomainEvents.Should().ContainSingle().Which.Should().BeOfType<OrderConfirmed>();
```

---

## Integration Tests — Testcontainers

Use a shared fixture per test class collection to avoid spinning up a container per test.

```csharp
// ResourceAccess.Tests/Infrastructure/DatabaseFixture.cs
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

[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }

// ResourceAccess.Tests/Orders/OrderRepositoryTests.cs
[Collection("Database")]
public class OrderRepositoryTests
{
    private readonly AppDbContext _db;
    private readonly OrderRepository _sut;

    public OrderRepositoryTests(DatabaseFixture fixture)
    {
        _db = fixture.DbContext;
        _sut = new OrderRepository(_db);
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

---

## Validator Tests — FluentValidation.TestHelper

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

## Test Builders

Use builder pattern for test data. Never construct domain objects or request objects
inline in tests — it makes tests brittle when constructors change.

```csharp
// Domain.Tests/Builders/OrderBuilder.cs
public class OrderBuilder
{
    private CustomerId _customerId = new(Guid.NewGuid());
    private OrderStatus _status = OrderStatus.Pending;

    public static OrderBuilder APendingOrder() => new();
    public static OrderBuilder AConfirmedOrder() => new OrderBuilder().WithStatus(OrderStatus.Confirmed);

    public OrderBuilder WithCustomer(CustomerId id) { _customerId = id; return this; }
    public OrderBuilder WithStatus(OrderStatus status) { _status = status; return this; }

    public Order Build() => Order.Reconstitute(_customerId, _status); // factory for test hydration
}
```

---

## Coverage Configuration

Add to each test `.csproj`:

```xml
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <CoverletOutputFormat>cobertura</CoverletOutputFormat>
  <CoverletOutput>./coverage/</CoverletOutput>
  <Threshold>80</Threshold>                  <!-- fail build below 80% -->
  <ThresholdType>line,branch,method</ThresholdType>
</PropertyGroup>
```

For Domain tests, set `<Threshold>100</Threshold>`.

Run coverage report locally:
```bash
dotnet test --collect:"XPlat Code Coverage"
reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:"coverage-report" -reporttypes:Html
```