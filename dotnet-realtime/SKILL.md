---
name: dotnet-realtime
description: Bridge between real-time communication patterns and .NET — SignalR hub setup, IHubContext broadcasting, group management, Redis backplane scaling, and frontend SignalR client wiring. Use when implementing live updates in a .NET backend via SignalR.
---

## Scope

This skill owns the **.NET realization of real-time patterns**. It specifies:

- SignalR hub definition and registration
- Broadcasting from application code via `IHubContext<T>`
- Group management for scoped broadcasts
- Authentication over WebSocket connections
- Redis backplane for horizontal scaling

---

## SignalR — Hub Definition

```csharp
// Hubs/ForumHub.cs
public class ForumHub : Hub
{
    // Clients join a group per thread they are viewing
    public async Task JoinThread(string threadId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"thread:{threadId}");
    }

    public async Task LeaveThread(string threadId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"thread:{threadId}");
    }
}
```

---

## Broadcasting from Application Code

Broadcast via `IHubContext<T>` from Managers or event handlers — never from the Hub itself.

```csharp
// In a Manager or event handler — NOT in the Hub
public class VoteWorkflowManager
{
    private readonly IHubContext<ForumHub> _hubContext;

    public async Task CastVoteAsync(CastVoteCommand command, CancellationToken ct)
    {
        // ... process vote, save, recalculate score ...

        await _hubContext.Clients
            .Group($"thread:{command.ThreadId}")
            .SendAsync("VoteUpdated", new { command.ThreadId, NewScore = score }, ct);
    }
}
```

Rules:
- Hubs handle connection lifecycle (join/leave groups). Business logic stays in Managers — broadcast via `IHubContext<T>`, not from the Hub.
- Use **groups** to scope broadcasts. A user viewing thread X should only receive updates for thread X.
- SignalR handles transport negotiation automatically (WebSocket → SSE → Long Polling). Do not force a specific transport unless debugging.
- For authentication, SignalR uses the same JWT/cookie auth as the API. Pass the token via query string for WebSocket connections (browsers cannot set headers on WebSocket handshake).

---

## Registration

```csharp
// Program.cs
builder.Services.AddSignalR();

// After MapControllers
app.MapHub<ForumHub>("/hubs/forum");
```

---

## Frontend Client

The frontend SignalR client setup (package installation, connection builder, reconnection handling) belongs in the frontend. Add `@microsoft/signalr` to the frontend project.

---

## Redis Backplane for Horizontal Scaling

When running multiple .NET instances behind a load balancer, SignalR messages must be broadcast across all instances. Use the Redis backplane.

```csharp
builder.Services.AddSignalR()
    .AddStackExchangeRedis(connectionString);
```

Rules:
- Messages are broadcast across all instances via Redis Pub/Sub.
- Connection count is the scaling bottleneck, not request throughput. Monitor active connections, not RPS.


