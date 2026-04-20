---
name: authorization
description: Authorization patterns for multi-user applications — RBAC, resource ownership, permission models, role hierarchies, and where authorization logic lives in layered architectures. Use whenever an application needs to control who can do what — role checks, ownership guards, moderation privileges, admin-only endpoints. Language and stack agnostic. Does NOT cover authentication (identity verification, JWT issuance, login flows) — that is an authentication concern. Does NOT cover framework-specific attributes or middleware.
---

## Core Concepts

| Term | Definition |
|---|---|
| **Authentication** (AuthN) | Verifying *who* the user is. Produces an identity (user ID, claims). |
| **Authorization** (AuthZ) | Deciding *what* an authenticated user is allowed to do. Consumes the identity. |
| **Permission** | A single action on a single resource type: `thread:delete`, `comment:edit`. |
| **Role** | A named collection of permissions: `Admin`, `Moderator`, `Member`. |
| **Policy** | A named rule that evaluates claims, roles, or resource state to produce allow/deny. |
| **Resource ownership** | The user who created a resource has implicit permissions on it (edit, delete). |

Rules:
- Authorization is a separate concern from authentication. Never mix "who are you?" with "are you allowed?"
- Every endpoint that mutates state or returns private data must have an explicit authorization rule. Unauthenticated access is the exception, not the default.
- Authorization rules are business logic — they belong in the domain or application layer, not in controllers or middleware alone.

---

## Permission Model

### Role-Based Access Control (RBAC)

Assign permissions to roles, assign roles to users. Simple and sufficient for most applications.

```
Role: Admin
  Permissions: [*]                          — all actions

Role: Moderator
  Permissions: [thread:lock, thread:pin, thread:delete,
                comment:delete, user:ban]

Role: Member
  Permissions: [thread:create, thread:edit:own, thread:delete:own,
                comment:create, comment:edit:own, comment:delete:own,
                vote:cast]

Role: Guest (unauthenticated)
  Permissions: [thread:read, comment:read]
```

Rules:
- Define roles as a closed set — do not allow users to create arbitrary roles unless building a permissions management system.
- Use the principle of least privilege: `Member` is the default role, not `Admin`.
- Keep the role set small (3–5 roles). If you need more than 5, consider whether you actually need attribute-based access control (ABAC).

### Attribute-Based Access Control (ABAC)

Evaluate arbitrary attributes (user properties, resource state, time, context) to make authorization decisions. More flexible than RBAC, more complex to implement and audit.

Use ABAC when:
- Permissions depend on resource state ("only draft threads can be edited")
- Permissions depend on relationships ("only the team lead can approve")
- The role model would require dozens of fine-grained roles

For most applications, RBAC + ownership checks is sufficient. Graduate to ABAC only when RBAC cannot express the rules.

---

## Resource Ownership

Ownership is the most common authorization pattern beyond role checks. The user who created a resource has permissions that other users of the same role do not.

```
Rule: thread:edit
  Allow if: user.role == Admin OR user.role == Moderator
  Allow if: user.id == thread.authorId AND thread.isDeleted == false

Rule: comment:delete
  Allow if: user.role == Admin OR user.role == Moderator
  Allow if: user.id == comment.authorId
```

Rules:
- Ownership checks require loading the resource before making the authorization decision. This is a read-then-check pattern — the authorization logic must have access to the resource.
- Never trust the client to send an `authorId` for ownership checks. Always read the resource from the database and compare against the authenticated user's ID.
- Ownership checks compose with role checks: "the author OR a moderator can delete."

---

## Role Hierarchies

Roles can inherit permissions from lower roles. This avoids duplicating permission lists.

```
Guest → Member → Moderator → Admin
  │        │          │          │
  │        │          │          └── all permissions
  │        │          └── Member permissions + moderation
  │        └── Guest permissions + create/edit own
  └── read-only
```

Rules:
- A higher role includes all permissions of lower roles. An `Admin` can do everything a `Moderator` can do.
- Implement hierarchy by checking "role is at least X" rather than "role is exactly X." This prevents bugs when a new role is added between existing ones.
- Store the role as a single value on the user, not as a set of flags. A user has one role at a time (unless you explicitly need multi-role assignment).

---

## Where Authorization Lives in Layered Architecture

Authorization is not a single-layer concern — it spans multiple layers with different responsibilities.

| Layer | Authorization responsibility |
|---|---|
| **Client / API** (controllers, middleware) | Coarse-grained gate: "is the user authenticated?", "does the user have the required role?" Reject obviously unauthorized requests before doing any work. |
| **Application** (managers, use cases) | Resource-level authorization: load the resource, check ownership or state-based rules, reject if unauthorized. This is where most authorization decisions happen. |
| **Domain** (engines, aggregates) | Invariant enforcement that happens to overlap with authorization: "only the order owner can cancel an order" may be an aggregate invariant, not just a permission check. |
| **Infrastructure** (repositories, queries) | Implicit authorization via query scoping: "a user only sees their own orders" is enforced by filtering in the repository, not by checking after the fact. |

Rules:
- The API layer handles **role gates** — reject requests from users who lack the required role before calling any business logic.
- The application layer handles **resource ownership** — load the resource, compare `authorId` to `currentUserId`, reject if unauthorized. This requires the resource to be loaded first.
- Never put all authorization in the API layer alone. Role gates catch broad violations, but ownership and state-based checks require business context.
- Never skip API-layer gates and rely solely on the application layer. Defense in depth — check at both layers.

---

## Cross-Context Authorization

In a multi-context system, each bounded context owns its own authorization rules. The identity context issues tokens with roles/claims; downstream contexts interpret those claims.

```
Identity Context
  └── Issues JWT with: { sub: userId, role: "Moderator" }

Forum Context
  └── Reads JWT claims
  └── Evaluates: role == Moderator → allow thread:lock
  └── Evaluates: userId == thread.authorId → allow thread:edit
```

Rules:
- The identity context owns *who the user is* and *what role they hold*. It does not know about forum threads or billing invoices.
- Downstream contexts own *what each role means* for their domain. "Moderator" means different things in a Forum context vs. a Billing context.
- Propagate identity via JWT claims. Downstream contexts must not call back to the identity context to check permissions — they must be self-contained using the claims in the token.
- If a downstream context needs additional identity data (display name, avatar), maintain a local read projection via events — do not call the identity API per request.

---

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| Checking roles with string literals everywhere | Fragile, impossible to audit | Define policies/permissions as named constants or an enum |
| Authorization in controllers only | Ownership and state checks are skipped | Add resource-level checks in the application layer |
| Trusting client-sent `authorId` | Trivial impersonation | Always load the resource and compare server-side |
| Admin bypasses all validation | Admin can create invalid data | Admin bypasses *authorization*, not *domain invariants* |
| No default deny | New endpoints are accidentally public | Require explicit authorization on every endpoint; use a global require-authenticated default with opt-out for public routes |
| Calling identity context per request | Latency, coupling | Use JWT claims + local read projections |
