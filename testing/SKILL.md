---
name: testing
description: Testing strategy and coverage requirements — component-specific testing approaches, test types, coverage targets, and test organization. Use when planning test strategy, determining what types of tests to write, setting coverage goals, organizing test projects, or deciding between unit vs integration tests. Platform, language, and architecture agnostic — does not assume any specific architectural pattern or layering model.
---

## Coverage Requirements

| Component Category | Minimum Coverage | Test Type |
|---|---|---|
| Core business logic (models, rules, events) | **100%** | Unit |
| Business rule services (stateless calculation/validation) | **90%** | Unit |
| Orchestration services (workflow coordination) | **80%** | Integration |
| Data access and external adapters (repositories, gateways) | **80%** | Integration |
| API entry points (controllers, endpoints, validators) | **80%** | Unit + Integration |
| Shared utilities | **80%** | Unit |
| **Overall project minimum** | **80%** | - |

Coverage is non-negotiable. When writing production code, write accompanying tests to meet these targets.

---

## Test Types

### Unit Tests
Test a single component in isolation. All dependencies are mocked or stubbed.

**Use for**:
- Core business logic (domain models, business rules)
- Business rule services (stateless logic with no I/O)
- Validators
- Utilities

**Characteristics**:
- Fast (<100ms per test)
- No external dependencies (database, network, file system)
- Deterministic (same input → same output)
- Run in parallel

### Integration Tests
Test multiple components working together with real dependencies.

**Use for**:
- Orchestration services (coordinating multiple components)
- Data access components (database operations)
- External API clients
- Full request/response flows

**Characteristics**:
- Slower (100ms - 5s per test)
- Real dependencies (database, message queues, etc.)
- May require setup/teardown
- May run sequentially if shared state

### End-to-End Tests
Test complete user scenarios through the public API.

**Use sparingly**:
- Critical user workflows
- Smoke tests for deployment validation
- Cross-system integration validation

**Characteristics**:
- Very slow (5s+ per test)
- Full application stack
- Brittle (many points of failure)
- Expensive to maintain

**Ratio**: Aim for 70% unit, 25% integration, 5% end-to-end.

---

## Component-Specific Testing Strategies

### Core Business Logic
**Target**: 100% coverage, all unit tests.

**Test**:
- Model state transitions and invariants
- Consistency boundary enforcement
- Immutable value type equality
- Event raising on meaningful state changes
- Business rule validation

**Do NOT mock**: Business logic objects are the thing being tested.

```
// Example test cases for Order
Order.Create_WithValidItems_CreatesOrder
Order.Create_WithEmptyItems_ThrowsException
Order.Confirm_WhenPending_SetsConfirmedStatusAndRaisesEvent
Order.Confirm_WhenAlreadyConfirmed_ThrowsException
Order.AddLine_UpdatesTotalCorrectly
```

---

### Business Rule Services
**Target**: 90% coverage, all unit tests.

**Test**:
- Business rule calculations
- Complex algorithms
- Edge cases and boundary conditions
- Error conditions

**Mock**: Any external dependencies (should be minimal for stateless services).

```
// Example test cases for PricingEngine
CalculatePrice_ForGoldCustomer_Applies20PercentDiscount
CalculatePrice_ForNewCustomer_AppliesNoDiscount
CalculatePrice_WithBulkOrder_AppliesTieredPricing
```

---

### Orchestration / Application Services
**Target**: 80% coverage, integration tests.

**Test**:
- Workflow orchestration (calling multiple components in correct order)
- Transaction boundaries
- Error handling and compensation
- Event dispatching

**Mock**: Only external services you don't control. Use real dependencies (e.g., test database) where possible.

```
// Example test cases for an order workflow service
PlaceOrder_WithValidData_SavesOrderAndPublishesEvent
PlaceOrder_WithInvalidData_DoesNotSaveAndThrowsException
PlaceOrder_WhenRepositoryFails_DoesNotPublishEvent
```

---

### Data Access (Repositories, Gateways, Adapters)
**Target**: 80% coverage, integration tests with real dependencies.

**Test**:
- CRUD operations
- Querying and filtering
- Transaction handling
- Optimistic concurrency

**Do NOT mock**: Database or external service. Use real instance (container, test service, etc.).

```
// Example test cases for OrderRepository
Save_NewOrder_InsertsIntoDatabase
Get_ExistingOrder_LoadsWithAllLines
Get_NonExistentOrder_ReturnsNull
SaveConcurrent_WithOptimisticLock_ThrowsConcurrencyException
```

---

### API Entry Points (Controllers, Endpoints)
**Target**: 80% coverage, mix of unit and integration tests.

**Unit tests for**:
- Validation logic
- Request/response mapping
- Error handling

**Integration tests for**:
- Full HTTP request/response cycle
- Authentication/authorization
- Content negotiation

```
// Example test cases
PlaceOrder_WithValidRequest_Returns201Created
PlaceOrder_WithInvalidRequest_Returns400ValidationProblem
GetOrder_WhenNotFound_Returns404NotFound
GetOrder_WithoutAuth_Returns401Unauthorized
```

---

## Test Organization

Keep all tests for a deployable unit in a **single test project/module**. Separate unit, integration, and end-to-end tests by folder and namespace — not by project. Separate projects per test type create churn (duplicated references, build config, fixtures) without solving anything that test filters (namespace, tag, or trait) don't solve more cheaply.

```
tests/
└── Tests/
    ├── Unit/
    │   ├── BusinessLogic/
    │   └── Orchestration/
    ├── Integration/
    │   ├── DataAccess/
    │   └── Api/
    └── EndToEnd/
```

Folder names should mirror your production project structure. The architecture bridge specifies which production projects exist and therefore which subfolders appear under each test type.

To run a subset (fast unit tests inner-loop, integration in CI, etc.), filter by the namespace or a tag using your test runner's native filter syntax. The platform-specific testing bridge shows the exact command.

---

## Test Naming Convention

```
[MethodUnderTest]_[Scenario]_[ExpectedResult]
```

**Examples**:
- `Confirm_WhenOrderIsPending_SetsStatusToConfirmed`
- `CalculatePrice_ForGoldCustomer_AppliesDiscount`
- `GetAsync_WhenOrderDoesNotExist_ReturnsNull`
- `Save_NewOrder_InsertsIntoDatabase`

---

## Test Structure Pattern (AAA)

```
Arrange — Set up test data and mocks
Act     — Execute the method being tested
Assert  — Verify the expected outcome
```

Keep each section clear and separated. One logical assertion per test (but multiple assertion statements are fine if verifying different aspects of same logical outcome).

---

## Test Data Builders

Use the builder pattern for complex test data. Never construct domain objects inline.

**Benefits**:
- Tests are less brittle (only specify what matters for that test)
- Reusable across multiple tests
- Self-documenting test intent
- Easy to create variations

```
# Bad — brittle, unclear intent
order = Order(
    id = newOrderId(),
    customerId = newCustomerId(),
    status = PENDING,
    createdAt = now(),
    lines = [...]
)

# Good — clear intent, flexible
order = OrderBuilder
    .aPendingOrder()
    .withCustomer(customerId)
    .build()
```

Language-specific idioms (`new`, constructor syntax, method-chaining style)
belong in the platform-specific testing bridge. The principle — explicit named
builder methods replacing positional constructor calls — is universal.

---

## What NOT to Test

- **Framework code**: Don't test your web framework, ORM, or runtime libraries
- **Third-party libraries**: Don't test library internals
- **Trivial code**: Auto-properties, simple getters/setters
- **Private methods**: Test through public API
- **DTOs without logic**: Only test if they contain validation or mapping logic

---

See [references/TEST-DOUBLES.md](references/TEST-DOUBLES.md) for mocks, stubs, fakes, and spies, and [references/TDD.md](references/TDD.md) for test-driven development workflow.
