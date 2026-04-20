---
name: realtime
description: Real-time communication patterns for web applications — WebSockets, Server-Sent Events (SSE), transport selection, scaling persistent connections, and reverse proxy configuration. Use when implementing live updates (vote counts, new replies, typing indicators, notifications), choosing a transport, designing real-time event flows, or wiring real-time into a multi-context system. Stack agnostic — applies to any backend and frontend. Does NOT cover message broker configuration or domain event design.
---

## When to Use Real-Time

| Feature | Needs real-time? | Transport |
|---|---|---|
| Live vote count updates | Yes | SSE or WebSocket |
| New reply appears without refresh | Yes | WebSocket |
| Typing indicator | Yes | WebSocket |
| Notification badge count | Yes | SSE or WebSocket |
| Thread list updates | No — polling or revalidation is sufficient | — |
| User profile changes | No | — |

Rules:
- Not every feature needs real-time. Use real-time for features where latency >5 seconds degrades the user experience. For everything else, use polling, `revalidatePath`, or TanStack Query's `refetchInterval`.
- Real-time adds operational complexity (persistent connections, state management, scaling). Justify each real-time feature before implementing it.

---

## Transport Comparison

| Transport | Direction | Reconnection | Protocol | Best for |
|---|---|---|---|---|
| **Server-Sent Events (SSE)** | Server → Client only | Built-in (`EventSource` auto-reconnects) | HTTP/1.1+ | Notifications, live feeds, score updates |
| **WebSockets** | Bidirectional | Manual (implement reconnection logic) | `ws://` / `wss://` | Chat, typing indicators, collaborative editing |

Rules:
- **Default to SSE** for server-to-client push (notifications, live scores, feed updates). SSE is simpler, uses standard HTTP, works through most proxies, and auto-reconnects.
- **Use WebSockets** only when bidirectional communication is required (client sends data to server over the persistent connection, not just HTTP requests).
- Platform-specific abstractions (e.g. SignalR for .NET) provide automatic transport negotiation and reconnection.

---

## Server-Sent Events (SSE)

### Backend Pattern (any language)

```
// Endpoint: GET /api/threads/{threadId}/events
// Response headers:
//   Content-Type: text/event-stream
//   Cache-Control: no-cache
//   Connection: keep-alive

// Event stream format:
event: vote_updated
data: {"threadId": "abc-123", "voteScore": 42}

event: new_reply
data: {"postId": "def-456", "authorDisplayName": "Jane"}
```

Rules:
- Set `Content-Type: text/event-stream` — this is what triggers the browser's `EventSource` API.
- Each event has an optional `event:` field (type) and a required `data:` field (JSON payload).
- Include an `id:` field per event so the client can resume from the last received event on reconnect (via `Last-Event-ID` header).
- Keep-alive: send a comment line (`: ping`) every 15–30 seconds to prevent proxies from closing idle connections.

### Frontend Pattern (Browser EventSource API)

```js
// Generic browser API — adapt to your framework's lifecycle management
const eventSource = new EventSource("/api/forum/threads/" + threadId + "/events");

eventSource.addEventListener("vote_updated", (e) => {
  const data = JSON.parse(e.data);
  // Update your UI state with data.voteScore
});

eventSource.addEventListener("new_reply", (e) => {
  const data = JSON.parse(e.data);
  // Refresh the replies list or append the new reply
});

// On cleanup (component unmount, page navigation, etc.):
eventSource.close();
```

Rules:
- `EventSource` auto-reconnects on network failure. Do not implement custom reconnection logic for SSE.
- Close the `EventSource` when the user navigates away or the component unmounts to prevent connection leaks.
- Framework-specific integration (React hooks, TanStack Query cache updates) belongs in the frontend, not here.

---

## Scaling Real-Time

Persistent connections (WebSocket, SSE) create stateful affinity between a client and a specific server instance. This complicates horizontal scaling.

| Approach | When to use |
|---|---|
| **Single instance** | MVP, <1000 concurrent connections |
| **Backplane** (e.g. Redis Pub/Sub) | Multiple backend instances behind a load balancer |
| **Sticky sessions** (SSE) | SSE behind a load balancer; configure affinity by cookie or IP |
| **Dedicated real-time service** | High connection count; isolate real-time from API scaling |

Rules:
- For multi-instance deployments, use a backplane (Redis Pub/Sub or equivalent) so messages broadcast across all instances.
- For SSE, ensure the load balancer supports HTTP/1.1 keep-alive and does not buffer responses (disable proxy buffering in Nginx: `proxy_buffering off`).
- Connection count is the scaling bottleneck, not request throughput. Monitor active connections, not RPS.

---

## Reverse Proxy Configuration for Real-Time

Persistent connections (WebSocket, SSE) require specific proxy configuration. The critical requirements:

- **WebSocket**: `proxy_http_version 1.1`, `Upgrade` and `Connection: upgrade` headers, high `proxy_read_timeout`.
- **SSE**: `proxy_buffering off` (buffered responses defeat streaming), high `proxy_read_timeout`.
- Both transports: set `proxy_read_timeout` to 24h+ to prevent the proxy from closing idle connections (default is 60s).


