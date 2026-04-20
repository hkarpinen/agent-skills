---
name: scalability
description: Scalability patterns for multi-service systems — connection pooling, read replicas, caching strategy, CDN, horizontal scaling, and database partitioning. Use when planning for production scale, optimizing database connections, designing a caching layer, or configuring a CDN. Stack agnostic — applies to any backend, database, or frontend technology. Does NOT cover application architecture or container orchestration (Kubernetes, ECS).
---

## Scaling Axes

| Axis | What it means | Common approach |
|---|---|---|
| Vertical | Bigger machine (more CPU, RAM) | First resort; simplest; has a ceiling |
| Horizontal | More instances of the same service | Stateless services behind a load balancer |
| Data partitioning | Split data across multiple stores | Sharding, read replicas, schema-per-tenant |

Rules:
- Scale vertically first — it is simpler and solves most problems up to a surprisingly high threshold.
- Scale horizontally only when vertical scaling hits a ceiling or when you need fault tolerance across instances.
- Application services must be stateless to scale horizontally. If a service holds in-memory state (sessions, caches), extract that state to a shared store (Redis, database) before adding instances.

---

## Connection Pooling

Every database connection has a cost: TCP handshake, authentication, memory on the server. Without pooling, each request opens and closes a connection — unsustainable under load.

### Application-Level Pooling

Most ORMs and database drivers include a built-in connection pool. Configure it.

| Setting | Recommended default | Purpose |
|---|---|---|
| Min pool size | 5 | Keep warm connections ready |
| Max pool size | 20–50 per instance | Cap total connections from one app instance |
| Connection lifetime | 300s (5 min) | Rotate connections to pick up DNS/failover changes |
| Idle timeout | 60s | Release unused connections |

Rules:
- Max pool size × number of app instances must not exceed the database server's `max_connections`. Leave headroom for admin connections.
- For PostgreSQL: default `max_connections` is 100. With 3 app instances at pool size 30, you consume 90 — dangerously close. Tune or add PgBouncer.
- Never set max pool size to "unlimited" or to 1.

### External Connection Pooler (PgBouncer)

When application-level pooling is insufficient — too many app instances, serverless functions, or connection-heavy workloads — place a pooler between the application and the database.

```
App instances  →  PgBouncer (few hundred client connections)  →  PostgreSQL (30 server connections)
```

Rules:
- Use **transaction mode** for most workloads (connection returned to pool after each transaction). Use **session mode** only if the app uses session-level features (prepared statements, temp tables).
- PgBouncer runs as a sidecar container or a separate Compose service.
- Application connection strings point to PgBouncer, not directly to PostgreSQL.

---

## Read Replicas

A read replica is a copy of the primary database that serves read queries. Write queries go to the primary; read queries go to one or more replicas.

```
Writes  →  Primary (read-write)
Reads   →  Replica 1, Replica 2 (read-only, eventually consistent)
```

Rules:
- Read replicas are **eventually consistent**. Writes on the primary may take milliseconds to seconds to propagate. Never read from a replica immediately after a write if the read must reflect that write.
- Use a separate connection string for read queries. The ORM or application layer routes based on query type.
- Read replicas reduce load on the primary but do not reduce write contention.
- Start with one primary and zero replicas. Add a replica when read query load becomes the bottleneck — not before.

---

## Caching Strategy

### Cache Hierarchy

```
Browser cache  →  CDN edge cache  →  Application cache (Redis)  →  Database
```

Each layer reduces load on the layer behind it. Configure from outermost (cheapest) to innermost (most expensive).

### Application Cache (Redis / Memcached)

| Pattern | Description | When to use |
|---|---|---|
| **Cache-aside** | App checks cache first; on miss, reads DB and writes to cache | Most read-heavy queries (user profiles, category lists) |
| **Write-through** | App writes to cache and DB simultaneously | Data that is read immediately after write |
| **Cache invalidation on event** | Subscribe to domain events; invalidate relevant cache keys | Multi-service systems where the writer and reader are different services |

Rules:
- Set a TTL on every cache entry. Never cache without expiration — stale data is inevitable.
- Use structured cache keys: `{context}:{entity}:{id}` (e.g., `forum:thread:abc-123`).
- Invalidate explicitly on writes. Do not rely on TTL alone for data that the user just changed.
- Cache misses are normal. The system must work correctly with an empty cache — cache is an optimization, not a data store.

---

## CDN — Static Assets and Edge Caching

A CDN caches static assets (images, CSS, JS bundles) at edge nodes close to users.

Rules:
- Serve all static assets through a CDN. This includes Next.js `/_next/static/` and SPA `dist/` output.
- Use content-hashed filenames for cache busting (Next.js and Vite do this by default).
- Set long `Cache-Control` headers for hashed assets: `public, max-age=31536000, immutable`.
- For HTML pages (non-hashed), use short TTLs or `stale-while-revalidate`.
- Never cache authenticated API responses at the CDN level.

---

## Horizontal Scaling Checklist

Before adding a second instance of any service, verify:

- [ ] **No local file state** — logs, uploads, temp files go to external storage (S3, shared volume)
- [ ] **No in-memory sessions** — use a session store (Redis, database) or stateless JWTs
- [ ] **No in-memory cache** — use an external cache (Redis) or accept per-instance cache divergence
- [ ] **Migrations run separately** — not on app startup, or guarded by a distributed lock
- [ ] **Background jobs are coordinated** — use a distributed job framework or leader election; do not run the same scheduled job on every instance
- [ ] **Health check endpoint exists** — the load balancer needs it

---

## Database Partitioning

### Table Partitioning (PostgreSQL)

For tables that grow unbounded (audit logs, events, time-series data), use PostgreSQL's native partitioning.

```sql
CREATE TABLE audit.events (
    id          uuid        NOT NULL,
    event_type  text        NOT NULL,
    payload     jsonb       NOT NULL,
    created_at  timestamptz NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE audit.events_2026_q1
    PARTITION OF audit.events
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
```

Rules:
- Partition by the column used in most queries (usually a timestamp).
- Create partitions ahead of time (scheduled job or migration). A missing partition causes insert failures.
- Drop old partitions instead of deleting rows — `DROP TABLE` is instant; `DELETE` is slow and bloats.
- Partition only tables that grow to millions of rows. Small tables do not benefit.


