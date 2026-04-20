---
name: media-storage
description: File upload, object storage, and image processing patterns for web applications. Use when implementing user avatars, inline images in user-generated content, file attachments, or any feature that stores and serves binary assets. Covers object storage (S3/MinIO), signed URLs, image resizing, and CDN integration. Stack agnostic — applies to any backend and frontend. Does NOT cover video processing, streaming media, or DRM.
---

## Storage Architecture

Never store uploaded files on the application server's local filesystem. Use object storage — it decouples storage from compute, survives container restarts, and scales independently.

```
Client  →  Backend API  →  Object Storage (S3 / MinIO / Azure Blob / GCS)
                                    ↓
                              CDN (optional)  →  Client
```

| Component | Purpose |
|---|---|
| Object storage | Durable binary storage with HTTP access |
| Presigned URLs | Time-limited upload/download URLs that bypass the backend |
| CDN | Edge cache for frequently accessed assets (avatars, thumbnails) |
| Image processing | Resize, crop, format conversion on upload |

---

## Upload Patterns

### Presigned URL Upload (Recommended)

The backend generates a presigned URL; the client uploads directly to object storage. The backend never handles the file bytes — this eliminates a throughput bottleneck.

```
1. Client  → POST /api/uploads/presign { filename, contentType }
2. Backend → generates presigned PUT URL (expires in 5 min)
3. Backend → returns { uploadUrl, objectKey }
4. Client  → PUT <uploadUrl> with file body (direct to S3/MinIO)
5. Client  → POST /api/threads { title, body, imageKey: objectKey }
6. Backend → validates objectKey exists, associates with entity
```

Rules:
- Set a short expiration on presigned URLs (5–15 minutes). They are single-use by convention.
- Validate the `Content-Type` and file size in the presigned URL policy — do not trust the client.
- After upload, the backend must verify the object exists before associating it with a domain entity.
- Never expose raw object storage URLs to users. Serve through a CDN or a proxy endpoint.

### Server-Side Upload (Simple, Small Files Only)

The client uploads to the backend; the backend forwards to object storage. Acceptable for small files (avatars < 5MB).

```
1. Client  → POST /api/users/me/avatar (multipart form)
2. Backend → validates file type and size
3. Backend → uploads to object storage
4. Backend → saves object key on user entity
5. Backend → returns { avatarUrl }
```

Rules:
- Set a request body size limit (e.g., 5MB for avatars, 20MB for attachments).
- Validate MIME type server-side — do not trust the `Content-Type` header from the client.
- Process (resize, strip metadata) before storing.

---

## Object Key Conventions

```
{context}/{entity-type}/{entity-id}/{purpose}.{ext}

Examples:
  identity/users/abc-123/avatar.webp
  forum/threads/def-456/images/img-001.webp
  forum/threads/def-456/images/img-002.webp
```

Rules:
- Include the bounded context and entity in the key path for organizational clarity.
- Use UUIDs or content hashes in the key — never user-supplied filenames (path traversal risk).
- Use a consistent image format (WebP for web) after processing.

---

## Image Processing

Process images on upload — not on read. Store the processed result.

| Operation | When |
|---|---|
| Resize to maximum dimensions | Always — prevent storing 50MP phone photos |
| Generate thumbnail | When a small preview is needed (avatar, thread list) |
| Convert to WebP | Always — smaller file size, universal browser support |
| Strip EXIF metadata | Always — EXIF can contain GPS coordinates and other PII |

### Size Presets

| Preset | Dimensions | Use case |
|---|---|---|
| `avatar-sm` | 64×64 | Comment author avatar |
| `avatar-md` | 128×128 | Profile page avatar |
| `avatar-lg` | 256×256 | Settings page preview |
| `content` | max 1200px wide | Inline images in posts |
| `thumbnail` | 300×200 | Thread list preview |

Rules:
- Generate all required sizes at upload time. Do not resize on every request.
- Use a server-side image processing library (Sharp for Node.js, ImageSharp for .NET, Pillow for Python).
- Set quality to 80% for WebP — visually indistinguishable from 100% at half the file size.
- Reject uploads that fail processing (corrupt files, unsupported formats) with a clear error message.

---

## MinIO for Local Development

MinIO is an S3-compatible object storage server that runs in Docker. Use it for local development parity with production S3.

```yaml
# In compose.yaml
services:
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"    # S3 API
      - "9001:9001"    # Web console
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD-SHELL", "mc ready local"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  minio_data:
```

Rules:
- Use the same S3 SDK/client for both MinIO (local) and AWS S3 (production). MinIO is wire-compatible.
- Configure the endpoint URL via environment variable: `S3_ENDPOINT=http://minio:9000` locally, omit or set to AWS endpoint in production.
- Create buckets on first run via an init container or application startup logic.
- Never commit MinIO credentials to version control. Use `.env`.

---

## CDN Integration

Serve processed images through a CDN for low-latency delivery.

Rules:
- Use content-hashed or versioned object keys (`avatar-abc123-v2.webp`) for cache busting. Alternatively, use the object's ETag.
- Set `Cache-Control: public, max-age=31536000, immutable` for content-addressed keys.
- For mutable keys (e.g., `avatar.webp` that can be re-uploaded), use short TTLs or invalidate on upload.
- The CDN origin points to the object storage bucket — not to the application server.

---

## Security

Rules:
- Never serve user-uploaded files from the same origin as the application. Use a separate domain or subdomain (`assets.example.com`) to prevent cookie-based attacks.
- Validate file types by inspecting magic bytes (file signature), not just the extension or MIME type.
- Set `Content-Disposition: inline` for images. Set `Content-Disposition: attachment` for all other file types to prevent browser execution.
- Scan uploaded files for malware if the system handles non-image files.
- Rate-limit upload endpoints to prevent storage abuse.

---

## Cross-Context Media Ownership

In a multi-context system, decide which bounded context owns the upload endpoint and storage path. The key question: **which context's aggregate does the media belong to?**

| Media type | Owning context | Rationale |
|---|---|---|
| User avatar | Identity | Avatar is a user profile attribute |
| Thread inline image | Forum | Image is part of forum content |
| Invoice PDF | Billing | Document belongs to billing domain |

### How the URL Propagates

When the Identity context processes an avatar upload, downstream contexts need the URL:

```
1. User uploads avatar → Identity context stores in object storage
2. Identity context updates user profile with avatar URL
3. Identity context publishes UserProfileUpdated { userId, displayName, avatarUrl }
4. Forum context consumes event → updates local user_projections table with avatarUrl
5. Forum reads avatarUrl from its own projection — never calls Identity API
```

Rules:
- The context that owns the aggregate owns the upload. Do not split upload responsibility across contexts.
- Downstream contexts store the media URL in their local projection, not the object key. The URL is the public contract.
- If the owning context changes or reprocesses the media (e.g. re-generates thumbnails), it publishes an event with the updated URL.
- All contexts use the same object storage instance (or bucket) but with different key prefixes per context (see Object Key Conventions above).
- The upload endpoint lives in the owning context's API. The frontend calls that context directly — the reverse proxy routes `/api/identity/uploads` to the identity API.


