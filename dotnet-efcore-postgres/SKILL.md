---
name: dotnet-efcore-postgres
description: Connects a .NET data-access layer to PostgreSQL using EF Core and Npgsql. Use when configuring EF Core with a PostgreSQL provider, setting up Npgsql, mapping models to PostgreSQL conventions, running migrations against PostgreSQL, or writing PostgreSQL-specific integration tests. Does NOT prescribe project names or solution layout — those are owned by the architecture bridge.
---

## Packages

Add to the project that owns the `DbContext`:

| Package | Purpose |
|---|---|
| `Npgsql.EntityFrameworkCore.PostgreSQL` | EF Core PostgreSQL provider |
| `EFCore.NamingConventions` | Automatic snake_case naming convention |

Add to the test project:

| Package | Purpose |
|---|---|
| `Testcontainers.PostgreSql` | Real PostgreSQL in Docker for integration tests |

---

## Provider Registration

This bridge owns the `dbOptions` action supplied to `AddDbContext<AppDbContext>`. The **composition root** and the method that ultimately calls `AddDbContext` are defined by your architecture.

```csharp
// In your composition root (architecture bridge specifies which project and method name).
var connectionString = builder.Configuration.GetConnectionString("Default");

Action<DbContextOptionsBuilder> dbOptions = options => options
    .UseNpgsql(connectionString, npgsql => npgsql
        .MigrationsAssembly("<DbContextAssemblyName>")   // assembly that owns DbContext + migrations
        .EnableRetryOnFailure(maxRetryCount: 3))
    .UseSnakeCaseNamingConvention();   // maps PascalCase → snake_case automatically

// Pass dbOptions to whichever registration method your architecture bridge defines.
// The method calls: services.AddDbContext<AppDbContext>(dbOptions);
```

---

## snake_case Naming Convention

`UseSnakeCaseNamingConvention()` automatically converts all EF Core PascalCase identifiers to `snake_case` at the database level.

```csharp
// EF Core property     → PostgreSQL column
// OrderId              → order_id
// CreatedAt            → created_at
// TotalAmount          → total_amount
```

---

## Entity Configuration

Follow PostgreSQL naming conventions (snake_case, plural tables, named constraints) in `IEntityTypeConfiguration<T>` implementations.

```csharp
public class OrderEntityConfiguration : IEntityTypeConfiguration<OrderEntity>
{
    public void Configure(EntityTypeBuilder<OrderEntity> builder)
    {
        builder.ToTable("orders", schema: "orders");

        builder.HasKey(o => o.Id).HasName("pk_orders");

        builder.Property(o => o.Id).ValueGeneratedNever();   // UUID from domain

        builder.Property(o => o.Status)
            .HasColumnType("text")
            .HasConversion<string>()
            .IsRequired();

        // Value object → owned columns (when composing with ddd-tactical-patterns)
        builder.OwnsOne(o => o.TotalAmount, money =>
        {
            money.Property(m => m.Amount)
                .HasColumnName("total_amount")
                .HasColumnType("numeric(19,4)");
            money.Property(m => m.Currency)
                .HasColumnName("total_currency")
                .HasColumnType("char(3)");
        });

        builder.HasIndex(o => o.CustomerId)
            .HasDatabaseName("ix_orders_customer_id");
    }
}
```

---

## Migrations

The architecture bridge specifies which project owns the `DbContext` and which is the startup project. Use those in the CLI invocation:

```bash
dotnet ef migrations add <Name> \
  --project src/<DbContextProject> \
  --startup-project src/<StartupProject>

dotnet ef database update \
  --project src/<DbContextProject> \
  --startup-project src/<StartupProject>
```

Rules:
- One migration per logical schema change
- Never edit a migration after it has been applied to any shared environment
- Apply in production via CI/CD, not at application startup
- Review generated SQL before applying

---

## Connection String Configuration

Never hardcode connection strings.

```json
// appsettings.Development.json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5432;Database=yourapp_dev;Username=app_user;Password=dev_password;Include Error Detail=true"
  }
}
```

Include `Include Error Detail=true` in development only.

---

## Multi-Context Database Configuration

When multiple bounded contexts share a PostgreSQL server, each context's `DbContext` targets its own isolated unit.

### Database-per-Context (Recommended)

Each context's connection string points to a different database on the same server. No EF Core schema configuration is needed — the context owns the entire database.

```json
// Identity app — appsettings.Development.json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5432;Database=identity;Username=app_user;Password=dev_password;Include Error Detail=true"
  }
}

// Forum app — appsettings.Development.json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5432;Database=forum;Username=app_user;Password=dev_password;Include Error Detail=true"
  }
}
```

In Docker Compose, the connection string uses the Compose service name as the host:
```
Host=db;Port=5432;Database=identity;Username=app;Password=...
Host=db;Port=5432;Database=forum;Username=app;Password=...
```

Use an init script to create the databases on first run.

### Schema-per-Context (Alternative)

All contexts share one database. Each `DbContext` targets a specific schema using `HasDefaultSchema`.

```csharp
// In OnModelCreating or a shared configuration base
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.HasDefaultSchema("identity");   // or "forum"
    modelBuilder.ApplyConfigurationsFromAssembly(typeof(IdentityDbContext).Assembly);
}
```

Rules:
- Use `HasDefaultSchema` in `OnModelCreating` — not per-entity. This ensures all tables and the migrations history table land in the correct schema.
- Set the migrations history table schema to match:
  ```csharp
  options.UseNpgsql(connectionString, npgsql => npgsql
      .MigrationsHistoryTable("__EFMigrationsHistory", "identity"));
  ```
- Each context runs its own `dotnet ef` commands independently. Migrations never cross schema boundaries.

### Compose Migration Services

When using a migration-as-a-service pattern with multiple contexts, define one migration service per context:

```yaml
services:
  migrate-identity:
    image: identity-migrations:latest
    depends_on:
      db: { condition: service_healthy }
    environment:
      ConnectionStrings__Default: Host=db;Port=5432;Database=identity;...
    restart: "no"

  migrate-forum:
    image: forum-migrations:latest
    depends_on:
      db: { condition: service_healthy }
    environment:
      ConnectionStrings__Default: Host=db;Port=5432;Database=forum;...
    restart: "no"

  identity-api:
    depends_on:
      migrate-identity: { condition: service_completed_successfully }

  forum-api:
    depends_on:
      migrate-forum: { condition: service_completed_successfully }
```

---

See [references/TYPE-MAPPINGS.md](references/TYPE-MAPPINGS.md) for PostgreSQL-specific type mappings (uuid, timestamptz, jsonb, enums, arrays) and [references/TESTCONTAINERS.md](references/TESTCONTAINERS.md) for integration testing setup.
