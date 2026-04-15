---
name: dotnet-testing
description: Bridge between testing strategy and .NET implementation — xUnit, Moq, FluentAssertions, and Testcontainers setup for .NET projects. Use when implementing tests in .NET, setting up test projects, configuring test infrastructure, using FluentAssertions syntax, setting up Testcontainers, or configuring Moq. Composes with testing skill for strategy and coverage requirements.
---

## Test Stack

| Purpose | Package |
|---|---|
| Test framework | `xunit` + `xunit.runner.visualstudio` |
| Mocking | `Moq` |
| Assertions | `FluentAssertions` |
| Validator testing | `FluentValidation.TestHelper` |
| Integration DB | `Testcontainers.PostgreSql` or `Testcontainers.MsSql` |
| Coverage collection | `coverlet.collector` |

---

## Project Setup

```bash
# Create test project
dotnet new xunit -n YourApp.Domain.Tests

# Add required packages
dotnet add package Moq
dotnet add package FluentAssertions
dotnet add package coverlet.collector

# For integration tests with database
dotnet add package Testcontainers.PostgreSql

# Reference production project
dotnet add reference ../src/YourApp.Domain/YourApp.Domain.csproj
```

---

## Test Class Structure

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
            .Which.Should().BeOfType<OrderConfirmed>();
    }

    [Theory]
    [InlineData(OrderStatus.Confirmed)]
    [InlineData(OrderStatus.Cancelled)]
    public void Confirm_WhenNotPending_ThrowsDomainException(OrderStatus status)
    {
        // Arrange
        var order = OrderBuilder.AnOrder().WithStatus(status).Build();

        // Act
        var act = () => order.Confirm();

        // Assert
        act.Should().Throw<DomainException>()
            .WithMessage("*pending*");
    }
}
```

---

## Moq — Mocking Rules

- Mock only interfaces, never concrete classes
- Never mock the domain model — test it directly
- Never mock `DbContext` — use Testcontainers for Resource Access tests
- Verify calls only when the call itself is the behavior under test

```csharp
public class OrderWorkflowManagerTests
{
    private readonly Mock<IOrderRepository> _repositoryMock = new();
    private readonly Mock<IPricingEngine> _pricingEngineMock = new();
    private readonly OrderWorkflowManager _sut;

    [Fact]
    public async Task PlaceOrderAsync_WhenValid_SavesOrderAndReturnsId()
    {
        // Arrange
        var command = PlaceOrderCommandBuilder.AValidCommand().Build();
        _pricingEngineMock
            .Setup(e => e.CalculatePrice(It.IsAny<PricingContext>()))
            .Returns(Money.Of(100, Currency.USD));

        // Act
        var result = await _sut.PlaceOrderAsync(command);

        // Assert
        result.Should().NotBeNull();
        _repositoryMock.Verify(r => r.SaveAsync(It.IsAny<Order>(), default), Times.Once);
    }
}
```

---

## Test Builders

Use builder pattern for test data. Never construct domain objects inline — it makes tests brittle.

```csharp
public class OrderBuilder
{
    private CustomerId _customerId = new(Guid.NewGuid());
    private OrderStatus _status = OrderStatus.Pending;

    public static OrderBuilder APendingOrder() => new();
    public static OrderBuilder AConfirmedOrder() => new OrderBuilder().WithStatus(OrderStatus.Confirmed);

    public OrderBuilder WithStatus(OrderStatus status) { _status = status; return this; }

    public Order Build() => Order.Reconstitute(_customerId, _status);
}
```

---

## Coverage Configuration

Add to each test `.csproj`:

```xml
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <CoverletOutputFormat>cobertura</CoverletOutputFormat>
  <Threshold>80</Threshold>
  <ThresholdType>line,branch,method</ThresholdType>
</PropertyGroup>
```

For Domain tests, set `<Threshold>100</Threshold>`.

---

See [references/FLUENTASSERTIONS.md](references/FLUENTASSERTIONS.md) for comprehensive FluentAssertions patterns and [references/TESTCONTAINERS.md](references/TESTCONTAINERS.md) for integration testing setup with Testcontainers.
