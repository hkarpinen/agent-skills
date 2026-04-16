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

```
test Confirm_WhenPending_SetsStatusToConfirmed
    order = OrderBuilder.APendingOrder().Build()
    
    order.Confirm()
    
    assert order.Status == Confirmed
// Test fails: Confirm() method doesn't exist
```

### 2. Green — Minimal implementation

```
Confirm()
    Status = Confirmed
// Test passes
```

### 3. Refactor — Add invariant check

```
Confirm()
    if Status != Pending
        throw "Only pending orders can be confirmed."
    Status = Confirmed
// Tests still pass
```

### 4. Red — Add test for invariant

```
test Confirm_WhenNotPending_ThrowsDomainException
    order = OrderBuilder.AConfirmedOrder().Build()
    
    assert calling order.Confirm() throws DomainException
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
