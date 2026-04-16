# Contributing

This document covers everything needed to add, update, or maintain skills in this repository.

---

## Repository Structure

```
skills-repo/
├── README.md                          ← consumer-facing: how to install and use
├── CONTRIBUTING.md                    ← this file
├── SKILL_TEMPLATE.md                  ← starting point for new skills
├── index.md                           ← agent registry — all skills, descriptions, pipelines
├── righting-software/                 ← each skill is a directory
│   ├── SKILL.md                       ← main skill content
│   └── references/                    ← optional detailed examples (loaded on demand)
│       ├── ANTI-PATTERNS.md
│       └── VOLATILITY-ANALYSIS.md
├── dotnet-webapi/
│   ├── SKILL.md
│   └── references/
├── db-postgres/
│   ├── SKILL.md
│   └── references/
└── ...
```

### Skill Categories

| Category | Purpose | Examples |
|---|---|---|
| Architecture | Design methodology, patterns, principles. No technology references. | `righting-software`, `ddd-strategic-patterns` |
| Domain Modeling | Domain patterns. Language agnostic — examples use pseudocode. | `ddd-tactical-patterns` |
| Backend | Language/stack-specific implementation conventions. | `dotnet-webapi` |
| Testing | Test strategy (agnostic) and platform-specific test bridges. | `testing`, `dotnet-testing` |
| Database | Database design conventions. Stack agnostic — no ORM references. | `db-postgres` |
| Frontend | Client-side framework conventions. Backend agnostic. | `react-spa`, `nextjs-app` |
| Infrastructure | Container and deployment patterns. Stack agnostic. | `docker` |
| Bridge | Connects two other skills. Owns the wiring that requires knowledge of both sides. | `dotnet-efcore-postgres`, `dotnet-idesign`, `ddd-idesign-bridge` |

---

## Skill Authoring Guide

### Skill Directory Layout

Every skill is a directory containing a `SKILL.md` file:

```
skill-name/
├── SKILL.md              ← main skill content (concise, <500 lines)
└── references/           ← optional detailed examples, loaded on demand
    └── TOPIC.md
```

`SKILL.md` must be fully readable in isolation — a consumer who loads only the main
file gets all rules and conventions. Reference files provide extended examples and
patterns that agents load when they need deeper detail on a specific topic.

### Required Sections

Every skill file must open with:

```markdown
---
name: skill-name
description: ...
---
```

| Field | Purpose |
|---|---|
| `name` | Unique skill identifier |
| `description` | What the skill does and when to use it (max 1024 chars). Include trigger keywords and what it does NOT cover. |

The `description` field is what agents read to decide whether to load the skill. Be specific about triggers. Include:
- The task types this skill applies to
- Specific terms or phrases that indicate this skill is needed
- What this skill does NOT cover (to avoid over-triggering)

### What Belongs in a Skill

A skill answers: *given a task in my domain, what should be done and how?*

- Concrete conventions, rules, and decisions — not explanations of why options exist
- Opinionated defaults — skills are not surveys of alternatives
- Examples and code samples where they clarify a rule
- Cross-references to composing skills where relevant (`**Composes with**`)

A skill does NOT contain:
- Content that belongs in another skill — never duplicate across skills
- Generic explanations of concepts the agent already knows
- Technology content in a technology-agnostic skill (and vice versa)
- Marketing language or justifications for the skill's existence

### Composition Model

Skills compose — a pipeline of 3-5 skills each owns a distinct concern. The boundary
between skills must be clean: if the same rule could reasonably live in two skills,
it belongs in exactly one and the other references it.

| Skill type | Owns | Does not own |
|---|---|---|
| Architecture | Design principles, layer rules, naming, anti-patterns | Any technology reference |
| Backend | Project structure, packages, DI wiring, framework conventions | Database schema design, ORM provider choice |
| Database | Schema conventions, types, indexes, constraints | ORM configuration, application code |
| Bridge | ORM provider config, type mappings, migration setup | Architecture rules, schema design decisions |

When a bridge skill exists between a backend and a database skill, the bridge owns
everything that requires knowledge of both sides. Neither the backend nor the database
skill should contain anything that requires knowing the other.

---

### Defining Pipelines

A pipeline is a named, ordered sequence of skills. Order encodes dependency: skills
earlier in the sequence produce context or artifacts that later skills depend on.

**Notation** (used in `index.md` and `README.md`):

| Symbol | Meaning |
|---|---|
| `→` | Sequential stage — apply left before right |
| `+` | Parallel — skills within a stage are independent |

Example:
```
`righting-software` → `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` → `dotnet-testing`
```

**Stage rules:**
1. `righting-software` is always stage 1 for any system-building or refactor pipeline — it produces the domain model and volatility decomposition that all other skills consume.
2. Backend and database skills are independent of each other (`+`) but both depend on the architecture stage.
3. Bridge skills are always after the backend and database skills they connect — they require both sides to be defined.
4. Testing skills are always the final stage — they require the production structure to exist first.

**Defining a new pipeline:**

1. Name it by goal, not by tools (✅ "Build a .NET Web API with PostgreSQL" not ❌ "righting-software + dotnet-webapi pipeline").
2. Add it to the **Common Pipelines** table in `index.md` using the `→` / `+` notation.
3. Add the pipeline to the **Skill Composition** table in `README.md`.

**When to create a new pipeline vs. extend an existing one:**
- New pipeline: the goal is meaningfully distinct (different domain, different entry point).
- Extend existing: the new skill is an additive step in an existing workflow (e.g. adding a new bridge skill to an existing backend + database pipeline).

---

### Tone and Format

- Imperative, not descriptive. "Use `uuid` for all PKs" not "UUIDs can be used for PKs".
- Rules before rationale. State the rule first, explain briefly if the reason is non-obvious.
- Named constraints and conventions. Never "use a constraint" — always "use a check
  constraint named `ck_{table}_{rule}`".
- Short code samples to illustrate rules, not to demonstrate the technology.

---

## Adding a New Skill

### 1. Write the skill file

Create a new directory and copy the template:

```bash
mkdir dotnet-console
cp SKILL_TEMPLATE.md dotnet-console/SKILL.md
```

### 2. Update `index.md`

Add a row to the appropriate table in `index.md`:

```markdown
| `dotnet-console` | `dotnet-console/SKILL.md` | Building a .NET console application... |
```

If the new skill belongs in an existing pipeline, add it to the relevant pipeline row
in the **Common Pipelines** table using `→` for ordered stages and `+` for parallel
skills within a stage. See **Defining Pipelines** below for the notation rules.

### 3. Update the release workflow

Add the new skill to `.github/workflows/release.yml`:

```yaml
zip dist/dotnet-console.skill dotnet-console/SKILL.md
```

### 4. Open a pull request

Skill changes are reviewed like code changes. The PR description should state:
- What the skill covers
- What it explicitly does not cover
- Which skills it composes with
- Any existing skills it overlaps with and how the boundary is drawn

---

## Updating an Existing Skill

- Edit the skill file directly.
- If the change affects `index.md` descriptions, update those too.
- If the change affects how the skill composes with another, check the other skill
  for any content that now needs updating.
- Never change a skill's filename — consumers may have it pinned by path.

---

## Versioning and Release Process

### Version scheme

This repo uses semantic versioning (`vMAJOR.MINOR.PATCH`) applied to the repo as a whole,
not per-skill. All skills in a release share the same version tag.

| Change type | Version bump |
|---|---|
| New skill added | MINOR |
| Existing skill updated (backwards compatible) | PATCH |
| Skill renamed, removed, or breaking content change | MAJOR |

### Releasing

1. Merge all changes to `main`.
2. Tag the release:
   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```
3. GitHub Actions builds `.skill` artifacts for every skill and attaches them to the
   GitHub release automatically.
4. Update the release notes to summarise what changed per skill.

### What consumers see

Consumers install skills via the [Agent Skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add hkarpinen/agent-skills --skill righting-software --skill dotnet-webapi
```

See `README.md` for preset commands that install common skill combinations.

---

## Checklist for New Skills

- [ ] Directory created with `SKILL.md` (copied from `SKILL_TEMPLATE.md`)
- [ ] Opens with `name`, `description` frontmatter
- [ ] `SKILL.md` is fully readable in isolation (<500 lines)
- [ ] Reference files (if any) are in `references/` and loaded on demand
- [ ] Contains no content that belongs in a composing skill
- [ ] Architecture/domain/database skills: no technology references in body; technology cross-refs only in `## Companion Skills` table at bottom
- [ ] Bridge skills: reference only their bridged pair, not unrelated skills
- [ ] Added to `index.md` table and pipeline rows
- [ ] Added to `README.md` Available Skills list and relevant presets
- [ ] PR opened with boundary description
