# Test Doubles: Mocks, Stubs, Fakes, and Spies

## Definitions

### Stub
Returns canned responses. No behavior verification.

**Use when**: You need a dependency to return specific values for the test.

```
repository.GetAsync(orderId) → returns pre-configured Order
```

### Mock
Records interactions and allows verification of calls.

**Use when**: You need to verify a method was called with specific arguments.

```
Verify: repository.SaveAsync(order) was called exactly once
```

### Fake
Working implementation with shortcuts (e.g., in-memory database).

**Use when**: Real implementation is too slow/complex, but you need realistic behavior.

```
InMemoryOrderRepository — stores orders in Dictionary<OrderId, Order>
```

### Spy
Real object that also records interactions.

**Use when**: You need both real behavior AND call verification.

---

## When to Use Each

| Scenario | Test Double |
|---|---|
| Method needs to return specific value | Stub |
| Verify method was called | Mock |
| Need simple, fast implementation | Fake |
| Need real behavior + verification | Spy |

---

## Mock vs Stub: The Critical Difference

**Stub**: State verification
```
// Stub returns value, we verify state change
var price = pricingService.Calculate(order);
price.Should().Be(Money.Of(100, Currency.USD));
```

**Mock**: Behavior verification
```
// Mock verifies the call itself is the behavior
mock.Verify(x => x.PublishAsync(It.IsAny<OrderCreated>()), Times.Once);
```

**Rule**: Use stubs by default. Use mocks only when the call itself is what you're testing.

---

## Over-Mocking Anti-Pattern

**Problem**: Mocking everything makes tests brittle and tightly coupled to implementation.

```
// ❌ Bad — over-mocked
customerMock = mock(Customer)
addressMock = mock(Address)
customerMock.Address returns addressMock
addressMock.Country returns "USA"
```

**Fix**: Use real objects where possible.

```
// ✅ Good — real domain objects
customer = CustomerBuilder
    .ACustomer()
    .InCountry("USA")
    .Build()
```

**Rule**: Only mock at architectural boundaries (repositories, external services, infrastructure).
