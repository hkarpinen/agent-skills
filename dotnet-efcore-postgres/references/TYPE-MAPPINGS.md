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
public class AppDbContext : IdentityDbContext<AppUser>
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<OrderEntity> Orders => Set<OrderEntity>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

        // Identity tables → identity schema
        builder.Entity<AppUser>().ToTable("users", "identity");
        builder.Entity<IdentityRole>().ToTable("roles", "identity");
        builder.Entity<IdentityUserRole<string>>().ToTable("user_roles", "identity");
        builder.Entity<IdentityUserClaim<string>>().ToTable("user_claims", "identity");
        builder.Entity<IdentityUserLogin<string>>().ToTable("user_logins", "identity");
        builder.Entity<IdentityRoleClaim<string>>().ToTable("role_claims", "identity");
        builder.Entity<IdentityUserToken<string>>().ToTable("user_tokens", "identity");
    }
}
```
