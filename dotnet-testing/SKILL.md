---
name: dotnet-testing
description: Bridge between testing strategy and .NET implementation — xUnit, Moq, FluentAssertions, and Testcontainers setup for .NET projects. Use when implementing tests in .NET, setting up test projects, configuring test infrastructure, using FluentAssertions syntax, setting up Testcontainers, or configuring Moq. Architecture agnostic — does not assume any specific project layout or domain modeling style.
---

## Test Stack

| Purpose | Package |
|---|---|
| Test framework | `xunit` + `xunit.runner.visualstudio` |
| Mocking | `Moq` |
| Assertions | `FluentAssertions` |
| Validator testing | `FluentValidation.TestHelper` |
| Integration DB | `Testcontainers.PostgreSql`, `Testcontainers.MsSql`, or other DB-specific package |
| Coverage collection | `coverlet.collector` |

---

## Project Setup

One test project covers every production project. Organize by test type via folders/namespaces, not by splitting into multiple test projects.

```bash
# Create the single test project under tests/
dotnet new xunit -o tests/Tests -n Tests

# Add required packages
dotnet add tests/Tests package Moq
dotnet add tests/Tests package FluentAssertions
dotnet add tests/Tests package coverlet.collector
dotnet add tests/Tests package Microsoft.AspNetCore.Mvc.Testing

# Reference every production project.
# The architecture specifies which projects exist and their paths.
```

Add the Testcontainers package appropriate for your database provider.

---

## Test Class Structure

```csharp
public class DiscountCalculatorTests
{
    [Fact]
    public void Calculate_WhenCustomerIsGoldTier_AppliesFifteenPercentDiscount()
    {
        // Arrange
        var calculator = new DiscountCalculator();

        // Act
        var result = calculator.Calculate(basePrice: 100m, tier: CustomerTier.Gold);

        // Assert
        result.Should().Be(85m);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(0)]
    public void Calculate_WhenBasePriceIsNotPositive_ThrowsArgumentException(decimal basePrice)
    {
        // Arrange
        var calculator = new DiscountCalculator();

        // Act
        var act = () => calculator.Calculate(basePrice, CustomerTier.Standard);

        // Assert
        act.Should().Throw<ArgumentException>()
            .WithMessage("*positive*");
    }
}
```

---

## Moq — Mocking Rules

- Mock only interfaces, never concrete classes
- Never mock business-logic objects — test them directly
- Never mock `DbContext` — use Testcontainers for data-access tests
- Verify calls only when the call itself is the behavior under test

```csharp
public class CheckoutServiceTests
{
    private readonly Mock<IPaymentGateway> _paymentMock = new();
    private readonly Mock<IOrderStore> _storeMock = new();
    private readonly CheckoutService _sut;

    public CheckoutServiceTests()
    {
        _sut = new CheckoutService(_paymentMock.Object, _storeMock.Object);
    }

    [Fact]
    public async Task ProcessAsync_WhenPaymentSucceeds_SavesOrder()
    {
        // Arrange
        _paymentMock
            .Setup(p => p.ChargeAsync(It.IsAny<decimal>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PaymentResult.Success);

        // Act
        var result = await _sut.ProcessAsync(orderId: Guid.NewGuid(), amount: 99.95m);

        // Assert
        result.Should().NotBeNull();
        _storeMock.Verify(s => s.SaveAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Once);
    }
}
```

---

## Test Builders

Use builder pattern for test data. Never construct objects inline — it makes tests brittle.

```csharp
public class CreateOrderRequestBuilder
{
    private Guid _customerId = Guid.NewGuid();
    private decimal _amount = 100m;

    public static CreateOrderRequestBuilder AValidRequest() => new();

    public CreateOrderRequestBuilder WithAmount(decimal amount) { _amount = amount; return this; }
    public CreateOrderRequestBuilder WithCustomerId(Guid id) { _customerId = id; return this; }

    public CreateOrderRequest Build() => new(_customerId, _amount);
}
```

---

## Coverage Configuration

Add to `Tests.csproj`. Use the overall 80 % target here — per-component thresholds (e.g. 100 % for core business logic) are enforced in CI by filtering the coverage report, not by separate projects.

```xml
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <CoverletOutputFormat>cobertura</CoverletOutputFormat>
  <Threshold>80</Threshold>
  <ThresholdType>line,branch,method</ThresholdType>
</PropertyGroup>
```

---

See [references/FLUENTASSERTIONS.md](references/FLUENTASSERTIONS.md) for comprehensive FluentAssertions patterns and [references/TESTCONTAINERS.md](references/TESTCONTAINERS.md) for integration testing setup with Testcontainers.
