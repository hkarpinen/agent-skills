# FluentAssertions Patterns

## Primitives

```csharp
result.Should().Be(expected);
result.Should().NotBeNull();
result.Should().BeGreaterThan(0);
```

## Strings

```csharp
message.Should().Contain("pending");
message.Should().StartWith("Order");
message.Should().NotBeNullOrEmpty();
```

## Collections

```csharp
items.Should().HaveCount(3);
items.Should().ContainSingle();
items.Should().BeEquivalentTo(expected);
items.Should().AllSatisfy(i => i.Status.Should().Be(OrderStatus.Active));
items.Should().Contain(x => x.Id == expectedId);
```

## Exceptions

```csharp
act.Should().Throw<InvalidOperationException>()
    .WithMessage("*pending*");

await act.Should().ThrowAsync<NotFoundException>();

act.Should().ThrowExactly<ArgumentNullException>()
    .And.ParamName.Should().Be("order");
```

## Domain Events

```csharp
order.DomainEvents.Should().ContainSingle()
    .Which.Should().BeOfType<OrderConfirmed>()
    .Which.OrderId.Should().Be(order.Id);

order.DomainEvents.Should().HaveCount(2);
order.DomainEvents.Should().ContainItemsAssignableTo<IDomainEvent>();
```

## Dates

```csharp
order.CreatedAt.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromSeconds(1));
order.CreatedAt.Should().BeBefore(DateTime.UtcNow);
```

## Nullability

```csharp
result.Should().NotBeNull();
result.Should().BeNull();
optionalValue.Should().BeNull();
```

## Object Comparison

```csharp
// Structural equality (ignores reference equality)
actual.Should().BeEquivalentTo(expected);

// Partial comparison
actual.Should().BeEquivalentTo(expected, options => options
    .Excluding(x => x.Id)
    .Excluding(x => x.CreatedAt));

// Exact type match
result.Should().BeOfType<Order>();

// Assignable type
result.Should().BeAssignableTo<IEntity>();
```
