---
name: dotnet-authorization
description: ASP.NET Core authorization bridge — policy definitions, [Authorize] attribute usage, IAuthorizationHandler for resource-based authorization, claims mapping, and global authorization defaults. Use when implementing authorization in a .NET Web API. Does NOT cover authentication (JWT, Identity setup). Does NOT define which roles exist or what they mean.
---

---

## Global Authorization Default

Require authorization on all endpoints by default. Opt out explicitly for public routes.

```csharp
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});
```

Then mark public endpoints explicitly:

```csharp
[AllowAnonymous]
[HttpPost("login")]
public async Task<ActionResult<AuthResponse>> Login(...) { }

[AllowAnonymous]
[HttpGet]
public async Task<ActionResult<PagedResponse<ThreadSummary>>> ListThreads(...) { }
```

Rules:
- `FallbackPolicy` applies to every endpoint that does not have an explicit `[Authorize]` or `[AllowAnonymous]` attribute. This is default-deny.
- Always set `FallbackPolicy` to `RequireAuthenticatedUser()`. Never leave it null — null means unauthenticated access is the default.
- Use `[AllowAnonymous]` sparingly — only for login, registration, public read endpoints, and health checks.

---

## Policy Definitions

Define named policies for role gates and claim checks. Register them in a single block.

```csharp
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();

    options.AddPolicy("AdminOnly", policy =>
        policy.RequireRole("Admin"));

    options.AddPolicy("ModeratorOrAdmin", policy =>
        policy.RequireRole("Admin", "Moderator"));

    options.AddPolicy("MemberOrAbove", policy =>
        policy.RequireRole("Admin", "Moderator", "Member"));
});
```

Rules:
- Define all policies in one place — either directly in `Program.cs` or in a dedicated `AuthorizationServiceExtensions.AddAuthorizationPolicies()` method.
- Prefer `[Authorize(Policy = "...")]` over `[Authorize(Roles = "...")]`. Policies are named, testable, and composable; raw role strings are scattered and fragile.
- Policy names are string constants. Define them in a static class to avoid typos:

```csharp
public static class Policies
{
    public const string AdminOnly = nameof(AdminOnly);
    public const string ModeratorOrAdmin = nameof(ModeratorOrAdmin);
    public const string MemberOrAbove = nameof(MemberOrAbove);
}
```

---

## Applying Policies

### Controller Level

```csharp
[ApiController]
[Route("api/threads")]
[Authorize(Policy = Policies.MemberOrAbove)]  // all endpoints require Member+
public class ThreadsController : ControllerBase
{
    [HttpGet]
    [AllowAnonymous]                            // override: public read
    public async Task<ActionResult<PagedResponse<ThreadSummary>>> List(...) { }

    [HttpPost]
    public async Task<ActionResult<ThreadResponse>> Create(...) { }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = Policies.ModeratorOrAdmin)]  // override: escalated
    public async Task<ActionResult> Delete(Guid id, ...) { }
}
```

Rules:
- Apply the most common policy at the controller level. Override per-action with more or less restrictive policies.
- `[AllowAnonymous]` on an action overrides the controller-level `[Authorize]`.
- Keep policy application in the controller (Client layer). The controller is the coarse-grained gate.

---

## Resource-Based Authorization

For ownership checks ("user can edit their own thread but not others'"), use `IAuthorizationHandler` with a custom requirement.

### Define the Requirement

```csharp
public class ResourceOwnerRequirement : IAuthorizationRequirement { }
```

### Define the Handler

```csharp
public class ResourceOwnerHandler : AuthorizationHandler<ResourceOwnerRequirement, IOwnedResource>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        ResourceOwnerRequirement requirement,
        IOwnedResource resource)
    {
        var userId = context.User.FindFirstValue(ClaimTypes.NameIdentifier);

        // Owner can always access
        if (userId is not null && resource.AuthorId.ToString() == userId)
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        // Moderator/Admin can also access
        if (context.User.IsInRole("Admin") || context.User.IsInRole("Moderator"))
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        return Task.CompletedTask; // requirement not met — will result in 403
    }
}
```

### The Resource Interface

```csharp
public interface IOwnedResource
{
    Guid AuthorId { get; }
}
```

Domain entities or DTOs implement this interface when they participate in ownership checks.

### Registration

```csharp
services.AddScoped<IAuthorizationHandler, ResourceOwnerHandler>();
```

### Usage in Application Layer

Resource-based authorization is called from the application layer (Manager / use case), not from the controller. The application layer has access to the loaded resource.

```csharp
public class ThreadManager
{
    private readonly IAuthorizationService _authz;
    private readonly IThreadRepository _threads;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public async Task UpdateAsync(Guid threadId, UpdateThreadCommand command, CancellationToken ct)
    {
        var thread = await _threads.GetAsync(threadId, ct)
            ?? throw new NotFoundException($"Thread {threadId} not found.");

        var user = _httpContextAccessor.HttpContext!.User;
        var result = await _authz.AuthorizeAsync(user, thread, new ResourceOwnerRequirement());

        if (!result.Succeeded)
            throw new ForbiddenException("You do not have permission to edit this thread.");

        thread.Update(command.Title, command.Body);
        await _threads.SaveAsync(thread, ct);
    }
}
```

Rules:
- Resource-based authorization happens in the **application layer**, not the controller. The controller does not have the resource loaded yet.
- Inject `IAuthorizationService` and call `AuthorizeAsync` with the loaded resource and the requirement.
- The handler evaluates ownership + role escalation. This keeps the "author OR moderator" logic in one place.
- Throw a typed `ForbiddenException` that the exception handler middleware maps to HTTP 403.
- The `IOwnedResource` interface should live in the domain layer — it expresses "this entity has an owner," which is a domain concept.

---

## Claims Mapping

Map identity claims to application-usable values. The JWT issued by the identity context carries claims; the downstream context reads them.

```csharp
// Helper extension for extracting the current user ID from claims
public static class ClaimsPrincipalExtensions
{
    public static Guid GetUserId(this ClaimsPrincipal principal)
    {
        var sub = principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? throw new UnauthorizedAccessException("User ID claim is missing.");
        return Guid.Parse(sub);
    }

    public static string GetRole(this ClaimsPrincipal principal)
    {
        return principal.FindFirstValue(ClaimTypes.Role)
            ?? throw new UnauthorizedAccessException("Role claim is missing.");
    }
}
```

Rules:
- Use `ClaimTypes.NameIdentifier` for user ID and `ClaimTypes.Role` for role. These are the standard claim types populated by ASP.NET Core Identity.
- Parse claims defensively — missing claims should throw early with a clear error, not produce `null` deep in business logic.
- Place claims helper extensions in the Client (API) layer — they depend on `System.Security.Claims` which is an ASP.NET Core concern.

---

## Testing Authorization

### Unit Testing Handlers

```csharp
[Fact]
public async Task Owner_can_edit_thread()
{
    var thread = new ThreadFaker().Generate();
    var user = CreateClaimsPrincipal(thread.AuthorId, "Member");

    var handler = new ResourceOwnerHandler();
    var context = new AuthorizationHandlerContext(
        [new ResourceOwnerRequirement()], user, thread);

    await handler.HandleAsync(context);

    context.HasSucceeded.Should().BeTrue();
}

[Fact]
public async Task Non_owner_member_cannot_edit_thread()
{
    var thread = new ThreadFaker().Generate();
    var user = CreateClaimsPrincipal(Guid.NewGuid(), "Member");

    var handler = new ResourceOwnerHandler();
    var context = new AuthorizationHandlerContext(
        [new ResourceOwnerRequirement()], user, thread);

    await handler.HandleAsync(context);

    context.HasSucceeded.Should().BeFalse();
}

[Fact]
public async Task Moderator_can_edit_any_thread()
{
    var thread = new ThreadFaker().Generate();
    var user = CreateClaimsPrincipal(Guid.NewGuid(), "Moderator");

    var handler = new ResourceOwnerHandler();
    var context = new AuthorizationHandlerContext(
        [new ResourceOwnerRequirement()], user, thread);

    await handler.HandleAsync(context);

    context.HasSucceeded.Should().BeTrue();
}

private static ClaimsPrincipal CreateClaimsPrincipal(Guid userId, string role)
{
    var claims = new[]
    {
        new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
        new Claim(ClaimTypes.Role, role)
    };
    return new ClaimsPrincipal(new ClaimsIdentity(claims, "Test"));
}
```

Rules:
- Authorization handlers are pure logic — test them with unit tests, not integration tests.
- Create `ClaimsPrincipal` directly in tests. Do not depend on the full Identity stack.
- Test each path: owner-allowed, non-owner-denied, escalated-role-allowed.
