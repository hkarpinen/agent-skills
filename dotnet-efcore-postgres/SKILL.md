---
name: dotnet-efcore-postgres
description: Connects a .NET Infrastructure layer to PostgreSQL using EF Core and Npgsql. Use when configuring EF Core with a PostgreSQL provider, setting up Npgsql, mapping domain models to PostgreSQL conventions, running migrations against PostgreSQL, or writing PostgreSQL-specific integration tests. Use alongside dotnet-webapi and db-postgres — this skill bridges the two.
---

## Packages

Add to `YourApp.Infrastructure`:

| Package | Purpose |
|---|---|
| `Npgsql.EntityFrameworkCore.PostgreSQL` | EF Core PostgreSQL provider |
| `EFCore.NamingConventions` | Automatic snake_case naming convention |

Add to `YourApp.Infrastructure.Tests`:

| Package | Purpose |
|---|---|
| `Testcontainers.PostgreSql` | Real PostgreSQL in Docker for integration tests |

---

## Provider Registration

The bridge skill owns the `dbOptions` action that `dotnet-webapi`'s `AddInfrastructure` accepts.

```csharp
// YourApp.Host.Api/Program.cs
var connectionString = builder.Configuration.GetConnectionString("Default");

Action<DbContextOptionsBuilder> dbOptions = options => options
    .UseNpgsql(connectionString, npgsql => npgsql
        .MigrationsAssembly("YourApp.Infrastructure")
        .EnableRetryOnFailure(maxRetryCount: 3))
    .UseSnakeCaseNamingConvention();   // maps PascalCase → snake_case automatically

builder.Services
    .AddUtilities()
    .AddDomain()
    .AddApplication()
    .AddInfrastructure(builder.Configuration, dbOptions);
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

Follow `db-postgres` conventions in `IEntityTypeConfiguration<T>` implementations.

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

        // Value object → owned columns
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

```bash
dotnet ef migrations add <Name> \
  --project YourApp.Infrastructure \
  --startup-project YourApp.Host.Api

dotnet ef database update \
  --project YourApp.Infrastructure \
  --startup-project YourApp.Host.Api
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

See [references/TYPE-MAPPINGS.md](references/TYPE-MAPPINGS.md) for PostgreSQL-specific type mappings (uuid, timestamptz, jsonb, enums, arrays) and [references/TESTCONTAINERS.md](references/TESTCONTAINERS.md) for integration testing setup.
