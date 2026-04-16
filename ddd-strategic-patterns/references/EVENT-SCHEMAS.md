# Event Schema Conventions

> **Scope**: Event payload structure, naming, versioning, and evolution rules for
> domain events that cross bounded context boundaries. These conventions apply to
> events published through the outbox (see `messaging` skill) and consumed by
> other contexts.

---

## Event Naming

Events are named as past-tense facts about something that happened in the publishing context.

| Convention | Example |
|---|---|
| `<context>.<aggregate>_<verb_past>` | `identity.user_registered` |
| `<context>.<aggregate>_<verb_past>` | `forum.thread_created` |
| `<context>.<aggregate>_<verb_past>` | `forum.post_moderated` |

Rules:
- Always past tense — events describe what **happened**, not what should happen.
- Prefix with the publishing context name. This prevents collisions and makes the event's origin clear to consumers.
- Use `snake_case` for the event type string. This is the value in the envelope's `type` field.
- Never name events as commands (`create_user`, `moderate_post`). Commands are imperative; events are declarative.

---

## Payload Structure

Every event payload is a flat or shallowly nested JSON object. It contains the minimum data needed by downstream consumers.

### Required Fields

| Field | Type | Purpose |
|---|---|---|
| The aggregate root ID | `uuid` | Identifies which aggregate the event belongs to |
| Fields that changed | varies | The new values after the state change |

### Example Payloads

```json
// identity.user_registered
{
  "userId": "f9e8d7c6-...",
  "email": "jane@example.com",
  "displayName": "Jane Doe"
}

// forum.thread_created
{
  "threadId": "a1b2c3d4-...",
  "forumId": "e5f6a7b8-...",
  "authorId": "f9e8d7c6-...",
  "title": "How to design aggregates?"
}

// forum.post_moderated
{
  "postId": "c9d0e1f2-...",
  "threadId": "a1b2c3d4-...",
  "moderatorId": "11223344-...",
  "reason": "spam",
  "action": "hidden"
}
```

Rules:
- Include only **IDs and changed fields**. Do not include the full aggregate state — consumers
  that need more data should query their own projections or request it via an API.
- Use the same naming conventions as the source schema: `camelCase` for JSON keys.
- Nested objects are acceptable for value objects (e.g. `"address": { "city": "...", "zip": "..." }`)
  but avoid deep nesting.
- Never include sensitive data (passwords, tokens, personally identifiable information beyond what
  consumers strictly need). If a consumer needs the user's email, include it; if not, omit it.

---

## Versioning Strategy

Events are contracts. Once published, consumers depend on their shape. Changing an event's
structure requires a versioning strategy.

### Append-Only Evolution (Preferred)

Add new optional fields to the existing event type. Existing consumers ignore fields they do not
recognize.

```json
// v1 — original
{ "userId": "...", "email": "...", "displayName": "..." }

// v1 + new field — backwards compatible
{ "userId": "...", "email": "...", "displayName": "...", "avatarUrl": "https://..." }
```

Rules:
- Adding a new optional field is always safe. Consumers that don't need it ignore it.
- Never remove a field from an event that consumers depend on. Deprecate it (stop populating it)
  only after confirming all consumers have migrated.
- Never change the type or semantic meaning of an existing field. If the meaning changes, create
  a new event type.

### New Event Type (Breaking Changes)

When a change is not backwards-compatible (removing a required field, changing a field's type,
restructuring the payload), introduce a new event type.

```
identity.user_registered      → original
identity.user_registered_v2   → new shape
```

Rules:
- Publish both the old and new event types during a migration window.
- Remove the old event type only after all consumers have migrated to the new version.
- The migration window length depends on how many consumers exist and how quickly they can be
  updated. For internal systems, 1–2 sprints is typical.

---

## Schema Registry (Optional)

For systems with many events and consumers, consider a schema registry to enforce contract
compatibility at publish time.

| Approach | When |
|---|---|
| No registry — convention-enforced (this document) | Small to medium systems, <20 event types, single team |
| JSON Schema files in a shared repo | Medium systems, multiple teams, CI validation |
| Confluent Schema Registry (Avro/Protobuf) | Large systems, Kafka-based, strict compatibility enforcement |

Rules:
- Start without a registry. Convention enforcement through code review and this document is
  sufficient for most systems.
- If you adopt a registry, validate compatibility in CI before merging changes to event schemas.
- The schema registry does not replace the event envelope — the envelope wraps the validated payload.

---

## Anti-Patterns

| Anti-pattern | Why it's wrong | Correct approach |
|---|---|---|
| Full aggregate state in payload | Couples consumers to producer's internal model | Include only IDs and changed fields |
| Command-style names (`create_user`) | Events are facts, not instructions | Past tense: `user_created` |
| Changing field types | Breaks deserialization in consumers | New event type with `_v2` suffix |
| No context prefix | Name collisions across contexts | Always prefix: `identity.user_registered` |
| Sensitive data in events | Violates least-privilege; audit/compliance risk | Include only what consumers need |
