---
name: ci-cd
description: CI/CD pipeline patterns using GitHub Actions for .NET and Next.js projects — build/test/deploy stages, migration script generation, Docker image publishing, and environment promotion. Use when setting up CI/CD pipelines, automating test runs, publishing container images, or running database migrations in deployment. Examples use GitHub Actions with .NET and Next.js; adapt the workflow syntax and steps for other CI platforms. Does NOT cover Kubernetes deployment manifests, Helm charts, or cloud-specific IaC (Terraform, Pulumi).
---

## Pipeline Stages

Every pipeline follows the same stage progression. No stage can be skipped.

```
Code Push  →  Build  →  Test  →  Publish  →  Deploy
```

| Stage | Purpose | Fails fast on |
|---|---|---|
| **Build** | Compile, restore dependencies, lint | Syntax errors, missing dependencies |
| **Test** | Run unit + integration tests | Logic errors, regressions |
| **Publish** | Build Docker images, push to registry | Image build failures |
| **Deploy** | Apply migrations, deploy containers | Infrastructure errors |

Rules:
- Every push to `main` triggers the full pipeline. Feature branches trigger Build + Test only.
- Each stage gates the next. A test failure blocks publishing. A publish failure blocks deployment.
- Keep the pipeline under 10 minutes for the Build + Test stages. Developers should get feedback before context-switching.

---

## Multi-Context Pipeline

In a mono-repo with multiple bounded contexts, each context has its own pipeline triggered by changes to its directory. Shared infrastructure changes (Compose, proxy config) trigger all pipelines.

```yaml
# .github/workflows/identity.yml
name: Identity
on:
  push:
    paths:
      - 'identity/**'
      - 'contracts/**'
      - '.github/workflows/identity.yml'
    branches: [main]
  pull_request:
    paths:
      - 'identity/**'
      - 'contracts/**'
```

Rules:
- Use `paths` filters to avoid rebuilding contexts that didn't change.
- Changes to `contracts/` (shared event schemas) trigger all downstream context pipelines.
- Each context pipeline is independent — identity and forum can deploy at different cadences.

---

## GitHub Actions — .NET Backend

```yaml
# .github/workflows/identity.yml
name: Identity

on:
  push:
    paths: ['identity/**', 'contracts/**']
    branches: [main]
  pull_request:
    paths: ['identity/**', 'contracts/**']

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: identity

    services:
      postgres:
        image: postgres:17-alpine
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: identity_test
        ports: ['5432:5432']
        options: >-
          --health-cmd="pg_isready -U test"
          --health-interval=5s
          --health-timeout=5s
          --health-retries=5

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'

      - name: Restore
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore --configuration Release

      - name: Test
        run: dotnet test --no-build --configuration Release --verbosity normal
        env:
          ConnectionStrings__Default: "Host=localhost;Port=5432;Database=identity_test;Username=test;Password=test"

  publish:
    needs: build-and-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./identity
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/identity:${{ github.sha }}
            ghcr.io/${{ github.repository }}/identity:latest
```

Rules:
- Use GitHub Actions `services` for integration test dependencies (PostgreSQL, RabbitMQ). They run as sidecar containers.
- Cache NuGet packages: add `actions/cache` keyed on `**/*.csproj` file hashes.
- Publish Docker images only on `main` (not on PRs). Tag with both the commit SHA and `latest`.
- Use GitHub Container Registry (`ghcr.io`) or your preferred registry.

---

## GitHub Actions — Next.js Frontend

```yaml
# .github/workflows/frontend.yml
name: Frontend

on:
  push:
    paths: ['frontend/**']
    branches: [main]
  pull_request:
    paths: ['frontend/**']

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - run: npm ci
      - run: npm run lint
      - run: npm run build
        env:
          NEXT_PUBLIC_API_URL: http://localhost
      - run: npm test

  publish:
    needs: build-and-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./frontend
          push: true
          build-args: |
            NEXT_PUBLIC_API_URL=${{ vars.NEXT_PUBLIC_API_URL }}
          tags: |
            ghcr.io/${{ github.repository }}/frontend:${{ github.sha }}
            ghcr.io/${{ github.repository }}/frontend:latest
```

---

## Database Migrations in CI/CD

Never apply migrations from the application at startup. Generate migration scripts in CI and apply them as a separate deployment step.

### Strategy 1: Idempotent SQL Script (Recommended)

```yaml
# In the build-and-test job
- name: Generate migration script
  run: |
    dotnet ef migrations script \
      --idempotent \
      --project src/Infrastructure \
      --startup-project src/Client \
      --output migrations.sql

- name: Upload migration artifact
  uses: actions/upload-artifact@v4
  with:
    name: migrations
    path: identity/migrations.sql
```

In the deploy job, apply the script:

```yaml
- name: Apply migrations
  run: |
    PGPASSWORD=${{ secrets.DB_PASSWORD }} psql \
      -h ${{ vars.DB_HOST }} \
      -U ${{ vars.DB_USER }} \
      -d identity \
      -f migrations.sql
```

### Strategy 2: Migration Bundle

```yaml
- name: Build migration bundle
  run: |
    dotnet ef migrations bundle \
      --self-contained \
      --project src/Infrastructure \
      --startup-project src/Client \
      --output migrate

- name: Run migration bundle
  run: ./migrate --connection "${{ secrets.CONNECTION_STRING }}"
```

Rules:
- **Review generated SQL** before applying to production. Add a manual approval gate for production deployments.
- Use `--idempotent` for SQL scripts — they can be safely re-run without errors.
- Migrations run **before** the new application version is deployed. The new code must work with both the old and new schema during the rollout window.
- Never include `Include Error Detail=true` in production connection strings.
- Store migration scripts as build artifacts for auditability.

---

## Environment Promotion

```
Feature Branch  →  PR  →  main  →  Staging  →  Production
                    ↑              ↑              ↑
                Build+Test    Build+Test+     Manual approval
                              Publish+Deploy  + Deploy
```

Rules:
- Staging mirrors production infrastructure. Use the same Docker images, same database engine version, same reverse proxy config.
- Production deployments require manual approval (GitHub Environments with required reviewers).
- Use environment-specific secrets and variables (GitHub Environments: `staging`, `production`).
- Never deploy directly to production from a feature branch.

---

## Secrets Management

| Secret type | Storage | Injected via |
|---|---|---|
| Database passwords | GitHub Secrets (per environment) | Environment variable in deploy step |
| JWT signing keys | GitHub Secrets | Environment variable |
| Docker registry token | GitHub Secrets | `docker/login-action` |
| API URLs, non-secret config | GitHub Variables | `${{ vars.* }}` |

Rules:
- Never echo secrets in CI logs. GitHub masks them automatically, but avoid `set -x` in scripts that handle secrets.
- Rotate secrets periodically. Use short-lived credentials where possible (OIDC for cloud providers).
- Use `${{ secrets.* }}` for sensitive values, `${{ vars.* }}` for non-sensitive configuration.


