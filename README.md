# Skills

A versioned library of AI agent skills for building maintainable software systems.
Skills are plain markdown files — agnostic of any specific AI tool.

---

## What is a skill?

A skill is a self-contained markdown file that gives an AI agent focused, opinionated
guidance for a specific concern. Skills compose — a typical project loads 3-5 skills
that each own a distinct concern and never duplicate each other.

---

## Installation

Install skills into a project using the install script:

```bash
# Install individual skills
curl -fsSL https://raw.githubusercontent.com/your-username/skills/main/install.sh \
  | sh -s -- righting-software dotnet-webapi dotnet-testing

# Install a preset pipeline
curl -fsSL https://raw.githubusercontent.com/your-username/skills/main/install.sh \
  | sh -s -- --preset dotnet-postgres-api
```

This creates a `.skills/` directory in your project and generates agent adapter files:

```
your-project/
├── .skills/
│   ├── index.md                  ← local registry of installed skills + versions
│   ├── architecture/
│   │   └── righting-software.md
│   └── backend/
│       ├── dotnet-webapi.md
│       └── dotnet-testing.md
├── CLAUDE.md                     ← Claude Code adapter
├── .github/
│   └── copilot-instructions.md   ← GitHub Copilot adapter
├── .cursor/
│   └── rules/
│       └── skills.md             ← Cursor adapter
└── .windsurfrules                ← Windsurf adapter
```

---

## Versioning

Skills are versioned via GitHub releases. The install script pins each skill to the
release tag at install time. Your local `.skills/index.md` tracks installed versions.

```bash
# Upgrade a skill to latest
./skills-upgrade.sh dotnet-webapi

# Upgrade all skills
./skills-upgrade.sh --all
```

---

## Skill Pipelines

Skills are designed to compose. Common pipelines:

| Goal | Skills |
|---|---|
| Design any system | `righting-software` |
| .NET Web API + PostgreSQL | `righting-software` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` |
| Add tests | `dotnet-testing` |
| Full greenfield .NET project | all of the above |
| Refactor existing codebase | `righting-software` + relevant stack skills |

---

## For AI Agents

Read `.skills/index.md` to discover available skills. Load relevant skill files
on demand based on the task. Do not load all skills upfront.

---

## Releases

Each GitHub release publishes `.skill` files as artifacts for direct download into
Claude.ai via Settings → Skills. The markdown source files are always the source
of truth — `.skill` files are build artifacts.

---

## Contributing

Each skill is a single markdown file. To add or update a skill:

1. Create or edit the `.md` file in the appropriate directory.
2. Update `index.md` with the skill entry.
3. Open a PR — skill changes are reviewed like code changes.
4. On merge to `main`, a release is tagged and `.skill` artifacts are built by CI.
