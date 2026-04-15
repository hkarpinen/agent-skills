#!/usr/bin/env sh
set -e

REPO="your-username/skills"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SKILLS_DIR=".skills"
VERSION="${BRANCH}"

# Presets — skills listed in execution order (left to right).
# Order: architecture first → backend + database (parallel) → bridge → testing.
PRESET_DOTNET_POSTGRES_API="righting-software dotnet-webapi db-postgres dotnet-efcore-postgres dotnet-testing"

# Skill file locations
skill_path() {
  case "$1" in
    righting-software)     echo "architecture/righting-software.md" ;;
    dotnet-webapi)         echo "backend/dotnet-webapi.md" ;;
    dotnet-testing)        echo "backend/dotnet-testing.md" ;;
    db-postgres)           echo "database/db-postgres.md" ;;
    dotnet-efcore-postgres)echo "bridge/dotnet-efcore-postgres.md" ;;
    *) echo "" ;;
  esac
}

usage() {
  echo "Usage: install.sh [--preset <name>] [skill1 skill2 ...]"
  echo ""
  echo "Presets:"
  echo "  dotnet-postgres-api   righting-software + dotnet-webapi + db-postgres + dotnet-efcore-postgres + dotnet-testing"
  echo ""
  echo "Skills:"
  echo "  righting-software, dotnet-webapi, dotnet-testing, db-postgres, dotnet-efcore-postgres"
  exit 1
}

install_skill() {
  SKILL="$1"
  PATH_IN_REPO=$(skill_path "$SKILL")

  if [ -z "$PATH_IN_REPO" ]; then
    echo "Unknown skill: $SKILL"
    exit 1
  fi

  DIR="${SKILLS_DIR}/$(dirname "$PATH_IN_REPO")"
  mkdir -p "$DIR"

  echo "Installing ${SKILL}..."
  curl -fsSL "${BASE_URL}/${PATH_IN_REPO}" -o "${SKILLS_DIR}/${PATH_IN_REPO}"
  echo "  ✓ ${SKILLS_DIR}/${PATH_IN_REPO}"
}

generate_adapters() {
  # CLAUDE.md
  cat > CLAUDE.md << 'EOF'
# Agent Instructions

Read `.skills/index.md` to discover available skills for this project.
Load relevant skill files on demand based on the task at hand.
Do not load all skills upfront — select only what the current task requires.
EOF
  echo "  ✓ CLAUDE.md"

  # GitHub Copilot
  mkdir -p .github
  cat > .github/copilot-instructions.md << 'EOF'
Read `.skills/index.md` to discover available skills for this project.
Load relevant skill files on demand based on the task at hand.
Do not load all skills upfront — select only what the current task requires.
EOF
  echo "  ✓ .github/copilot-instructions.md"

  # Cursor
  mkdir -p .cursor/rules
  cat > .cursor/rules/skills.md << 'EOF'
Read `.skills/index.md` to discover available skills for this project.
Load relevant skill files on demand based on the task at hand.
Do not load all skills upfront — select only what the current task requires.
EOF
  echo "  ✓ .cursor/rules/skills.md"

  # Windsurf
  cat > .windsurfrules << 'EOF'
Read `.skills/index.md` to discover available skills for this project.
Load relevant skill files on demand based on the task at hand.
Do not load all skills upfront — select only what the current task requires.
EOF
  echo "  ✓ .windsurfrules"
}

generate_local_index() {
  mkdir -p "$SKILLS_DIR"
  cat > "${SKILLS_DIR}/index.md" << EOF
# Installed Skills

Pinned to: ${VERSION}
Source: https://github.com/${REPO}

Read this file first. Load skill files on demand — only what the current task requires.

## Skills

| Skill | File | When to use |
|---|---|---|
EOF

  for SKILL in "$@"; do
    PATH_IN_REPO=$(skill_path "$SKILL")
    case "$SKILL" in
      righting-software)      DESC="Designing systems, decomposing services, reviewing architecture. Always load for any design or refactor task." ;;
      dotnet-webapi)          DESC=".NET Web API project setup, packages, DI, EF Core, Serilog, Identity, OpenTelemetry." ;;
      dotnet-testing)         DESC="Writing tests in .NET — xUnit, Moq, FluentAssertions, Testcontainers, coverage rules." ;;
      db-postgres)            DESC="PostgreSQL schema design — naming, types, indexes, constraints. Stack agnostic." ;;
      dotnet-efcore-postgres) DESC="Connecting .NET Infrastructure to PostgreSQL via EF Core + Npgsql." ;;
    esac
    echo "| \`${SKILL}\` | \`${PATH_IN_REPO}\` | ${DESC} |" >> "${SKILLS_DIR}/index.md"
  done

  echo "  ✓ ${SKILLS_DIR}/index.md"
}

# Parse args
if [ $# -eq 0 ]; then usage; fi

SKILLS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --preset)
      shift
      case "$1" in
        dotnet-postgres-api) SKILLS="$PRESET_DOTNET_POSTGRES_API" ;;
        *) echo "Unknown preset: $1"; usage ;;
      esac
      ;;
    --*) echo "Unknown option: $1"; usage ;;
    *)   SKILLS="$SKILLS $1" ;;
  esac
  shift
done

echo "Installing skills..."
for SKILL in $SKILLS; do
  install_skill "$SKILL"
done

echo "Generating local index..."
generate_local_index $SKILLS

echo "Generating agent adapters..."
generate_adapters

echo ""
echo "Done. Skills installed to .skills/"
echo "Add .skills/ to version control. Agent adapters (CLAUDE.md etc.) are already generated."
