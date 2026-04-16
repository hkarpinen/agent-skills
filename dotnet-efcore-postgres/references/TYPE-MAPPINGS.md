# PostgreSQL Type Mappings in EF Core

## uuid

EF Core with Npgsql maps `Guid` to `uuid` automatically. Ensure `ValueGeneratedNever()` so the domain generates the ID.

```csharp
builder.Property(o => o.Id).ValueGeneratedNever();
```

## timestamptz

Npgsql maps `DateTime` (UTC) to `timestamptz`. Configure at the context level to enforce UTC:

```csharp
// In AppDbContext constructor or OnConfiguring
AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", false);
```

Use `DateTimeOffset` for maximum correctness — Npgsql maps it to `timestamptz` natively.

## jsonb

```csharp
builder.Property(e => e.Payload)
    .HasColumnType("jsonb")
    .HasConversion(
        v => JsonSerializer.Serialize(v, JsonOptions),
        v => JsonSerializer.Deserialize<EventPayload>(v, JsonOptions)!);
```

## Enums

Map domain enums to PostgreSQL text (more migration-friendly than PostgreSQL enum types):

```csharp
builder.Property(o => o.Status)
    .HasConversion<string>()
    .HasColumnType("text");
```

To use native PostgreSQL enum types, register them:

```csharp
.UseNpgsql(connectionString, npgsql => npgsql
    .MapEnum<OrderStatus>("order_status", "orders"))
```

## Arrays

```csharp
// string[] maps to text[] automatically with Npgsql
builder.Property(p => p.Tags)
    .HasColumnType("text[]");
```

## AppDbContext Setup

```csharp
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<OrderEntity> Orders => Set<OrderEntity>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

If your project uses ASP.NET Core Identity, `dotnet-webapi` specifies how to
inherit from `IdentityDbContext<AppUser>` and map Identity tables to a dedicated
schema. That is a `dotnet-webapi` concern, not a DB-bridge concern.
```
