# Detailed Implementation Examples

> **Scope**: ASP.NET Core framework details only.
> `AppDbContext`, `IEntityTypeConfiguration<T>`, table/column naming, schema
> separation, and any other provider-specific persistence mapping live in the
> DB bridge skill (e.g. `dotnet-efcore-postgres`).
> `ServiceExtensions` naming, composition order, and which project registers
> what live in the architecture bridge (e.g. `dotnet-idesign`).

---

## FluentValidation — Request Validator

```csharp
public class PlaceOrderRequestValidator : AbstractValidator<PlaceOrderRequest>
{
    public PlaceOrderRequestValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty();
        RuleFor(x => x.Lines).NotEmpty().WithMessage("Order must have at least one line.");
        RuleForEach(x => x.Lines).ChildRules(line =>
        {
            line.RuleFor(l => l.ProductId).NotEmpty();
            line.RuleFor(l => l.Quantity).GreaterThan(0);
        });
    }
}
```

Register once per assembly that ships validators:

```csharp
builder.Services.AddValidatorsFromAssemblyContaining<PlaceOrderRequestValidator>();
```

---

## ASP.NET Core Identity — `AppUser`

Derive from `IdentityUser` to add profile fields while keeping Identity's
built-in authentication columns.

```csharp
public class AppUser : IdentityUser
{
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
}
```

---

## JWT Token Service

```csharp
internal sealed class JwtTokenService : ITokenService
{
    private readonly JwtSettings _settings;
    public JwtTokenService(IOptions<JwtSettings> settings) => _settings = settings.Value;

    public string GenerateToken(AppUser user, IList<string> roles)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id),
            new(ClaimTypes.Email, user.Email!),
        };
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_settings.Secret));
        var token = new JwtSecurityToken(
            issuer: _settings.Issuer,
            audience: _settings.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_settings.ExpiryMinutes),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
```

---

## HTTP Resilience — Typed Client

```csharp
services.AddHttpClient<IPaymentGateway, StripePaymentGateway>(client =>
    client.BaseAddress = new Uri(configuration["Stripe:BaseUrl"]!))
    .AddStandardResilienceHandler();
```

`AddStandardResilienceHandler()` provides retries, circuit breaker, and
timeout out of the box. Only customize if you have measured requirements that
the defaults fail to meet.

---

## Identity + JWT Registration Block

This fragment goes inside whichever `Add*` extension your architecture bridge
assigns to the Identity/auth concern (in `dotnet-idesign`: `AddInfrastructure`).

```csharp
services.AddIdentity<AppUser, IdentityRole>(options =>
{
    options.Password.RequiredLength = 12;
    options.Lockout.MaxFailedAccessAttempts = 5;
    options.User.RequireUniqueEmail = true;
})
.AddEntityFrameworkStores<AppDbContext>()
.AddDefaultTokenProviders();

services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    var jwt = configuration.GetSection("Jwt").Get<JwtSettings>()!;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwt.Issuer,
        ValidAudience = jwt.Audience,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Secret)),
        ClockSkew = TimeSpan.Zero
    };
});

services.AddScoped<ITokenService, JwtTokenService>();
```

---

## Serilog — `appsettings.json`

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.EntityFrameworkCore": "Warning"
      }
    },
    "WriteTo": [
      { "Name": "Console" },
      { "Name": "File", "Args": { "path": "logs/app-.log", "rollingInterval": "Day" } }
    ],
    "Enrich": [ "FromLogContext", "WithMachineName", "WithThreadId" ]
  }
}
```

---

## OpenTelemetry — Full Registration

```csharp
services.AddOpenTelemetry()
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddOtlpExporter())
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddOtlpExporter());
```

Environment variables (inject at runtime, not baked into the image):

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_SERVICE_NAME=YourApp
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

---

## Refresh Tokens

Short-lived access tokens (5–15 min) paired with long-lived refresh tokens (7–30 days) balance security with UX. When the access token expires, the client uses the refresh token to obtain a new pair without re-authenticating.

### Refresh Token Entity

```csharp
public class RefreshToken
{
    public Guid Id { get; init; }
    public string Token { get; init; } = string.Empty;
    public string UserId { get; init; } = string.Empty;
    public DateTimeOffset ExpiresAt { get; init; }
    public DateTimeOffset CreatedAt { get; init; }
    public DateTimeOffset? RevokedAt { get; set; }
    public string? ReplacedByToken { get; set; }

    public bool IsExpired => DateTimeOffset.UtcNow >= ExpiresAt;
    public bool IsRevoked => RevokedAt is not null;
    public bool IsActive => !IsRevoked && !IsExpired;
}
```

### Token Rotation

On every refresh, revoke the old token and issue a new pair (access + refresh). This prevents replay of stolen refresh tokens.

```csharp
public async Task<AuthResponse> RefreshAsync(string token, CancellationToken ct)
{
    var existing = await _db.RefreshTokens
        .SingleOrDefaultAsync(t => t.Token == token, ct)
        ?? throw new SecurityTokenException("Invalid refresh token");

    if (!existing.IsActive)
    {
        // Token reuse detected — revoke entire family
        await RevokeDescendantsAsync(existing, ct);
        throw new SecurityTokenException("Token has been revoked");
    }

    // Rotate
    var newRefreshToken = GenerateRefreshToken(existing.UserId);
    existing.RevokedAt = DateTimeOffset.UtcNow;
    existing.ReplacedByToken = newRefreshToken.Token;
    _db.RefreshTokens.Add(newRefreshToken);
    await _db.SaveChangesAsync(ct);

    var user = await _userManager.FindByIdAsync(existing.UserId);
    var roles = await _userManager.GetRolesAsync(user!);
    var accessToken = _jwtTokenService.GenerateToken(user!, roles);

    return new AuthResponse(accessToken, newRefreshToken.Token);
}
```

### Generation

```csharp
private RefreshToken GenerateRefreshToken(string userId)
{
    return new RefreshToken
    {
        Id = Guid.NewGuid(),
        Token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64)),
        UserId = userId,
        ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
        CreatedAt = DateTimeOffset.UtcNow
    };
}
```

Rules:
- Generate refresh tokens with `RandomNumberGenerator` — never `Guid.NewGuid()`. Refresh tokens must be cryptographically random.
- Store refresh tokens in the database, not in cookies or local storage on the server side.
- On every refresh request, rotate: revoke the old token and issue a new one.
- If a revoked token is presented, revoke the entire token family (all descendants) — this detects token theft.
- Set a hard expiration on refresh tokens (e.g. 7 days). Users must re-authenticate after that window.
- Clean up expired and revoked tokens periodically (scheduled job or migration).
