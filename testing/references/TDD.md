# Test-Driven Development (TDD) Workflow

## The Red-Green-Refactor Cycle

```
1. Red    — Write a failing test
2. Green  — Write minimal code to make it pass
3. Refactor — Improve code while keeping tests green
```

Repeat for each small behavior increment.

---

## Step-by-Step Example

### 1. Red — Write failing test

```csharp
[Fact]
public void Confirm_WhenPending_SetsStatusToConfirmed()
{
    var order = OrderBuilder.APendingOrder().Build();
    
    order.Confirm();
    
    order.Status.Should().Be(OrderStatus.Confirmed);
}
// Test fails: Confirm() method doesn't exist
```

### 2. Green — Minimal implementation

```csharp
public void Confirm()
{
    Status = OrderStatus.Confirmed;
}
// Test passes
```

### 3. Refactor — Add invariant check

```csharp
public void Confirm()
{
    if (Status != OrderStatus.Pending)
        throw new DomainException("Only pending orders can be confirmed.");
    
    Status = OrderStatus.Confirmed;
}
// Tests still pass
```

### 4. Red — Add test for invariant

```csharp
[Fact]
public void Confirm_WhenNotPending_ThrowsDomainException()
{
    var order = OrderBuilder.AConfirmedOrder().Build();
    
    var act = () => order.Confirm();
    
    act.Should().Throw<DomainException>();
}
// Test passes because we already added the check
```

---

## Benefits

- **Design pressure**: Writing tests first forces you to think about API usability
- **Minimal code**: Only write code needed to pass tests
- **Fast feedback**: Know immediately if something breaks
- **Living documentation**: Tests show how code is intended to be used

---

## When to Use TDD

**Good for**:
- Domain logic and business rules
- Complex algorithms
- Refactoring existing code

**Not necessary for**:
- Exploratory coding (spike solutions)
- Trivial code (getters/setters)
- Prototyping

---

## TDD vs Test-After

**TDD**: Test → Code → Refactor
**Test-After**: Code → Test

Both are valid. TDD provides better design feedback, but test-after is faster for simple implementations.

**Rule**: Use TDD for complex domain logic. Test-after is fine for infrastructure and simple CRUD.
