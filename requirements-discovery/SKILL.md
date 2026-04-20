---
name: requirements-discovery
description: Guided discovery process for turning vague application requests into clear, buildable requirements. Use when a user says "build me a X app" or describes a project without specifying user roles, system boundaries, MVP scope, data ownership, or key workflows. Run this skill BEFORE selecting architecture or implementation skills. Does NOT cover technical design, architecture, or stack selection.
---

## Core Principle

> **Never start building until you can state what you are building, for whom, and what "done" looks like.**

An underspecified request produces correct code for the wrong product. Discovery
is cheaper than rework. The agent's job is to surface assumptions, fill gaps,
and get explicit confirmation before writing a single line of code.

---

## When to Trigger Discovery

Start this process when a request exhibits any of these signals:

- The user describes the app by analogy only ("like Reddit", "a Trello clone")
- No user roles are named
- No workflows or use cases are described — only nouns ("a forum with posts and comments")
- Scope is unbounded ("build me a full-stack app")
- Non-functional requirements (auth, real-time, notifications) are absent or vague
- The user says "just start" or "you decide" for product-level decisions

Do **not** trigger discovery for targeted technical questions ("add pagination
to the orders endpoint") or when the user has already provided a detailed spec.

---

## Discovery Phases

Work through phases sequentially. Do not skip phases. Present findings as a
summary after each phase and ask for confirmation before proceeding.

### Phase 1 — Purpose and Users

Goal: understand *what* the product does and *who* uses it.

Questions to ask:
- What problem does this application solve? (one sentence)
- Who are the distinct user roles? (e.g., anonymous visitor, registered member, moderator, admin)
- What can each role do that the others cannot?
- Is there a public-facing surface (unauthenticated access), or is everything behind login?

Exit: a confirmed list of user roles with one-line capability descriptions.

### Phase 2 — Core Workflows

Goal: enumerate the key things users actually *do*.

Questions to ask:
- What are the 3–5 most important actions a user performs? (verb-noun: "create post", "cast vote", "assign task")
- For each action: who initiates it, what data is required, what happens on success, what happens on failure?
- Are there approval flows, state machines, or multi-step processes?
- What triggers notifications or alerts?

Exit: a confirmed list of use cases as verb-noun pairs, each with actor, inputs, and outcomes.

### Phase 3 — Data and Ownership

Goal: identify the main data entities and who owns them.

Questions to ask:
- What are the primary "things" in the system? (posts, orders, projects, etc.)
- Who creates each thing? Who can modify or delete it?
- Are there relationships between things? (a post belongs to a thread, a thread belongs to a forum)
- Is any data shared across boundaries, or does each area own its own data?
- What data is user-generated content vs. system-managed?

Exit: a confirmed list of key entities with ownership and relationships.

### Phase 4 — Boundaries and Integration

Goal: identify natural seams in the system.

Questions to ask:
- Are there parts of the system that could change independently? (e.g., billing vs. content, identity vs. forum)
- Does the system need to integrate with any external services? (payment providers, email services, OAuth providers, CDN)
- Are there areas with different scaling needs? (read-heavy vs. write-heavy)
- Does any part of the system need real-time updates? Which screens and what data?

Exit: a list of candidate boundaries with integration points noted.

### Phase 5 — MVP Scope

Goal: draw the line between "must have for launch" and "later."

Questions to ask:
- If you could only ship 3 features, which would they be?
- What can be manual or admin-only at first? (e.g., moderation via database instead of admin UI)
- What features are explicitly out of scope for now?
- Is there a hard deadline or external constraint?

Exit: a two-column list — MVP (build now) and Deferred (build later) — confirmed by the user.

### Phase 6 — Non-Functional Requirements

Goal: surface the implicit expectations.

Questions to ask:
- How do users authenticate? (email/password, OAuth, magic link, SSO)
- What authorization model is needed? (role-based, resource ownership, both)
- Are there performance expectations? (page load time, concurrent users)
- Is offline access or mobile needed?
- What environments are required? (local dev, staging, production)
- Any compliance or data residency requirements?

Exit: a confirmed list of non-functional requirements.

---

## Assumption Surfacing

Throughout discovery, follow these rules:

- **State every assumption explicitly.** If the user says "a forum app," do not
  silently assume anonymous reading is allowed, that there are moderators, or
  that posts support markdown. State each assumption and ask.
- **Never infer technical decisions from product requirements.** "Users need
  real-time updates" does not mean WebSockets — it means a requirement exists.
  Tech selection happens after discovery.
- **Flag missing negative requirements.** Ask what the system should *not* do.
  ("Can anyone delete anyone's post, or only their own and moderators?")
- **Challenge scope creep in real time.** If a new feature surfaces mid-phase,
  note it and ask: "Is this MVP or deferred?"

---

## Discovery Summary Format

After completing all phases, present a single summary document for the user to
approve, reject, or revise. Use this structure:

```
## Discovery Summary

### Purpose
One-sentence product description.

### User Roles
- Role: what they can do

### Core Workflows (MVP)
1. Verb-Noun — actor, inputs, outcome

### Core Workflows (Deferred)
1. Verb-Noun — reason for deferral

### Key Entities
- Entity — owner, key relationships

### Boundaries
- Boundary name — what it owns, integration points

### Non-Functional Requirements
- Requirement — detail

### Open Questions
- Anything unresolved
```

Rules:
- Do not proceed to architecture or implementation until the user explicitly
  approves the summary.
- If the user changes their mind on any item, update the summary and
  re-confirm.
- The summary is a living document during discovery — not a contract. Keep it
  concise and revisable.

---

## Anti-Patterns

| Anti-pattern | Why it's harmful | Instead |
|---|---|---|
| Jumping to code after Phase 1 | Builds features for the wrong users with missing workflows | Complete all phases before implementation |
| Asking "anything else?" as the only follow-up | Puts the burden on the user to know what's missing | Ask specific, pointed questions per phase |
| Inferring auth strategy without asking | Auth is the most common source of rework | Always ask Phase 6 auth questions explicitly |
| Treating the first answer as final | Users refine their thinking through conversation | Summarize, reflect back, and confirm |
| Mixing discovery with technical design | Anchors product decisions to premature tech choices | Keep discovery product-focused; tech comes after |
| Skipping MVP scoping | Everything becomes "must have" and nothing ships | Always run Phase 5 |

---

## Exit Criteria

Discovery is complete when:

- [ ] All six phases have been addressed
- [ ] Every assumption has been stated and confirmed or rejected
- [ ] The summary document has been presented and explicitly approved
- [ ] Open questions list is empty or the user has accepted the unknowns
- [ ] MVP vs. deferred scope is clearly drawn

After approval, the agent proceeds to architecture and implementation using the
appropriate skills. The discovery summary serves as the requirements reference
throughout the build.
