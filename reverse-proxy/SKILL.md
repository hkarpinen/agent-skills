---
name: reverse-proxy
description: Reverse proxy patterns for multi-service systems — unified routing, TLS termination, and static asset serving. Use when multiple backend services and a frontend need a single entry point, when configuring Nginx or Traefik as a gateway, or when exposing a multi-app system via a single domain. Stack agnostic. Does NOT cover API gateway features like rate limiting, auth offloading, or request transformation at scale — those are API gateway concerns beyond basic routing.
---

## When to Use a Reverse Proxy

A reverse proxy sits in front of multiple services and routes requests to the correct backend based on path, hostname, or headers.

| Scenario | Need a reverse proxy? |
|---|---|
| Local development with separate ports per service | No — Compose networking + separate ports is fine |
| Production with multiple services behind one domain | Yes |
| Single service behind a CDN or cloud load balancer | No — the cloud LB is the proxy |
| Multiple services, no cloud LB, deployed on VMs or bare Compose | Yes |

---

## Routing Patterns

### Path-Based Routing (Most Common)

```
https://example.com
  /                     → frontend (Next.js or SPA)
  /api/identity/*       → identity-api
  /api/forum/*          → forum-api
  /static/*             → CDN or static file server
```

Rules:
- Route API paths by bounded context prefix: `/api/identity/`, `/api/forum/`.
- The frontend catches all non-API routes — return `index.html` for SPA or let Next.js handle routing.
- Strip the context prefix before forwarding to the backend if the backend expects paths without it.

### Host-Based Routing

```
api.example.com         → backend API
forum.example.com       → forum API
example.com             → frontend
```

Use when services are on separate subdomains. Requires wildcard DNS or per-subdomain DNS records.

---

## Nginx Configuration

```nginx
# nginx.conf
upstream identity_api {
    server identity-api:8080;
}

upstream forum_api {
    server forum-api:8080;
}

upstream frontend {
    server frontend:3000;
}

server {
    listen 80;
    server_name localhost;

    # Identity API
    location /api/identity/ {
        proxy_pass http://identity_api/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Forum API
    location /api/forum/ {
        proxy_pass http://forum_api/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Frontend (catch-all)
    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Rules:
- Always set `X-Forwarded-For`, `X-Forwarded-Proto`, and `Host` headers. Backend services need these for correct URL generation and security decisions.
- The `proxy_pass` trailing slash matters: `proxy_pass http://backend/api/` strips the matched location prefix. Without the trailing slash, the full path is forwarded.
- Use `upstream` blocks for backend services — they resolve Compose service names.

---

## Traefik Configuration (Labels-Based)

Traefik auto-discovers services via Docker labels — no config files needed.

```yaml
# compose.yaml
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  identity-api:
    build: ./identity
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.identity.rule=PathPrefix(`/api/identity`)"
      - "traefik.http.services.identity.loadbalancer.server.port=8080"
      - "traefik.http.middlewares.strip-identity.stripprefix.prefixes=/api/identity"
      - "traefik.http.routers.identity.middlewares=strip-identity"

  forum-api:
    build: ./forum
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.forum.rule=PathPrefix(`/api/forum`)"
      - "traefik.http.services.forum.loadbalancer.server.port=8080"
      - "traefik.http.middlewares.strip-forum.stripprefix.prefixes=/api/forum"
      - "traefik.http.routers.forum.middlewares=strip-forum"

  frontend:
    build: ./frontend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=PathPrefix(`/`)"
      - "traefik.http.routers.frontend.priority=1"
      - "traefik.http.services.frontend.loadbalancer.server.port=3000"
```

Rules:
- Set `exposedbydefault=false` — only services with `traefik.enable=true` labels are routed.
- Mount the Docker socket read-only (`:ro`) — Traefik reads container metadata but should not write.
- Set explicit priorities when routes overlap. The frontend catch-all (`/`) must have the lowest priority.
- `stripprefix` middleware removes the context prefix so backends receive clean paths.

---

## TLS Termination

Terminate TLS at the reverse proxy. Internal traffic between the proxy and backend containers is unencrypted — they share a Docker network.

Rules:
- Use Let's Encrypt for automated certificate management. Both Nginx (via Certbot) and Traefik (built-in ACME) support it.
- Never terminate TLS inside application containers for local development. Use HTTP internally.
- In production, redirect all HTTP traffic to HTTPS at the proxy level.
- Set `X-Forwarded-Proto: https` so backend services know the original request was secure.

---

## Docker Compose Integration

```yaml
# Add the proxy to your multi-service compose.yaml
services:
  proxy:
    image: nginx:1.27-alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - identity-api
      - forum-api
      - frontend
    restart: unless-stopped
```

Rules:
- The proxy is the only service that exposes ports to the host. Backend services and the frontend are accessible only through the proxy.
- Remove direct port mappings from backend services when using a proxy — they only need to be reachable on the Compose network.
- The proxy depends on all routed services.

---

## Companion Skills

| When you need | Skill |
|---|---|
| Docker Compose patterns and security hardening | `docker` |
| Multi-service Compose orchestration | `docker` (Multi-Service Compose section) |
| Backend containerization | The backend Docker bridge (e.g. `dotnet-webapi-docker`) |
| Frontend containerization | `nextjs-docker` |
