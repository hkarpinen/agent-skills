---
name: db-postgres
description: PostgreSQL schema design conventions — how to translate domain models into PostgreSQL idioms. Use when designing or reviewing a PostgreSQL database schema, choosing data types, defining indexes, constraints, or schema separation. Stack and ORM agnostic — applies regardless of the application stack. Composes with a bridge skill that maps these conventions to a specific ORM.
---

## Core Philosophy

- The schema serves the domain model — not the other way around
- Schema boundaries should reflect logical boundaries in the domain
- Use PostgreSQL-native features where they encode domain rules better than generic SQL

---

## Naming Conventions

All identifiers use `snake_case`.

| Concept | Convention | Example |
|---|---|---|
| Schema | `snake_case`, domain noun | `orders`, `identity`, `billing` |
| Table | `snake_case`, plural noun | `orders`, `order_lines`, `customers` |
| Column | `snake_case`, singular | `customer_id`, `created_at`, `total_amount` |
| Primary key column | always `id` | `id` |
| Foreign key column | `{referenced_table_singular}_id` | `order_id`, `customer_id` |
| Index | `ix_{table}_{columns}` | `ix_orders_customer_id` |
| Unique constraint | `uq_{table}_{columns}` | `uq_customers_email` |
| Check constraint | `ck_{table}_{rule}` | `ck_order_lines_quantity_positive` |

Never use reserved words as identifiers.

---

## Schema Separation

Separate schemas by domain concern, mirroring logical domain boundaries. Never put everything in `public`.

```sql
CREATE SCHEMA IF NOT EXISTS orders;
CREATE SCHEMA IF NOT EXISTS customers;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS identity;   -- auth / user management
CREATE SCHEMA IF NOT EXISTS audit;      -- domain events / audit trail
```

Rules:
- One schema per logical domain concern
- Infrastructure concerns (identity, audit) get their own schemas
- Cross-schema foreign keys are a warning sign
- `public` is reserved for shared extensions

---

## Primary Keys

All tables use `uuid` as the primary key.

```sql
CREATE TABLE orders.orders (
    id  uuid  NOT NULL,
    CONSTRAINT pk_orders PRIMARY KEY (id)
);
```

Where the UUID is generated is a **stack decision**, not a schema decision —
this skill does not prescribe it. Pick one of:

| Option | When to use |
|---|---|
| Application-layer generation (domain factory / ORM) | Default for DDD-style codebases where the aggregate owns its identity before persistence; required if domain events reference the new ID before `INSERT` |
| `DEFAULT gen_random_uuid()` on the column (pgcrypto) | CRUD-shaped apps where the domain has no need for the ID before write |
| Database sequence → application cast | Legacy integration where downstream systems consume sequential IDs |

Your application stack's bridge skill specifies
which option it uses and how to wire it. Do not mix strategies within one
database.

---

## Timestamps

All timestamp columns use `timestamptz` (timestamp with time zone). Never use `timestamp` without time zone.

```sql
created_at  timestamptz  NOT NULL  DEFAULT now(),
updated_at  timestamptz  NOT NULL  DEFAULT now(),
deleted_at  timestamptz  NULL                      -- for soft delete
```

---

## Standard Data Types

| Domain concept | PostgreSQL type |
|---|---|
| Aggregate identity / PK | `uuid` |
| Bounded text | `varchar(n)` |
| Unbounded text | `text` |
| Monetary amount | `numeric(19,4)` |
| Currency code | `char(3)` |
| Boolean | `boolean` |
| Whole number | `integer` |
| Timestamp | `timestamptz` |
| Date only | `date` |

---

## Constraints

Define all constraints explicitly with named constraints.

```sql
CREATE TABLE orders.order_lines (
    id          uuid          NOT NULL,
    order_id    uuid          NOT NULL,
    quantity    integer       NOT NULL,
    unit_price  numeric(19,4) NOT NULL,

    CONSTRAINT pk_order_lines             PRIMARY KEY (id),
    CONSTRAINT fk_order_lines_orders      FOREIGN KEY (order_id)
                                              REFERENCES orders.orders (id)
                                              ON DELETE CASCADE,
    CONSTRAINT ck_order_lines_quantity    CHECK (quantity > 0),
    CONSTRAINT ck_order_lines_unit_price  CHECK (unit_price >= 0)
);
```

Foreign key `ON DELETE` actions:
- `CASCADE` — child deleted with parent (for owned entities)
- `RESTRICT` — prevents parent deletion if children exist
- `SET NULL` — orphans the child (use only when valid)

---

## Indexing Strategy

- Every foreign key column needs an explicit index
- Add indexes for columns in frequent `WHERE`, `ORDER BY`, or `JOIN` clauses
- Do not add indexes speculatively

```sql
CREATE INDEX ix_order_lines_order_id   ON orders.order_lines (order_id);
CREATE INDEX ix_order_lines_product_id ON orders.order_lines (product_id);
```

---

## Normalization

- Normalize to 3NF by default
- Denormalize only with measured performance justification
- Embedded types (components without independent identity) map to columns on the parent table
- Many-to-many always use explicit junction table
- Never store comma-separated values

---

## Bridges to Application Stacks

This skill stops at the schema. The mapping from application code to the schema
above — ORM configuration, type conversion, UUID generation strategy, migration
tooling, integration tests — lives in a stack-specific bridge:

| Stack | Bridge skill |
|---|---|
| .NET (EF Core + Npgsql) | `dotnet-efcore-postgres` |

When composing this skill with an application stack, load the corresponding
bridge too. The bridge is authoritative on where the application-side
conventions (e.g. snake_case naming, UUID generation) come from.

---

## Pagination

Use keyset (cursor-based) pagination. Offset-based pagination (`LIMIT n OFFSET m`) degrades as
the offset increases because the database must scan and discard `m` rows before returning `n`.

### Keyset Pagination Pattern

```sql
-- First page
SELECT id, title, created_at
  FROM forum.threads
 WHERE deleted_at IS NULL
 ORDER BY id
 LIMIT 20;

-- Subsequent pages (cursor = last id from previous page)
SELECT id, title, created_at
  FROM forum.threads
 WHERE deleted_at IS NULL
   AND id > :cursor
 ORDER BY id
 LIMIT 20;
```

Rules:
- The cursor column must have a unique, sortable index. `id` (uuid) or a composite `(created_at, id)` works.
- Always `ORDER BY` the cursor column. Without a stable sort order, pages overlap or skip rows.
- Fetch `LIMIT + 1` rows to determine if a next page exists, then return only `LIMIT` rows to the caller.
- Never use `OFFSET` for paginated API endpoints. `OFFSET` is acceptable only for one-off admin queries or reports.

### Composite Cursor (sort by non-unique column)

When sorting by a non-unique column (e.g. `created_at`), add the primary key as a tiebreaker:

```sql
SELECT id, title, created_at
  FROM forum.threads
 WHERE deleted_at IS NULL
   AND (created_at, id) > (:cursor_created_at, :cursor_id)
 ORDER BY created_at, id
 LIMIT 20;
```

Index to support this:

```sql
CREATE INDEX ix_threads_created_at_id ON forum.threads (created_at, id)
    WHERE deleted_at IS NULL;
```

---

## Soft Delete

Use a `deleted_at` timestamp column instead of physically deleting rows. This preserves audit
history and allows restoration.

```sql
ALTER TABLE forum.threads ADD COLUMN deleted_at timestamptz NULL;
```

### Conventions

| Column | Type | Meaning |
|---|---|---|
| `deleted_at` | `timestamptz NULL` | `NULL` = active; non-null = soft-deleted at that timestamp |

Rules:
- **Every query that returns active records** must include `WHERE deleted_at IS NULL`. Missing this
  filter is the most common soft-delete bug.
- Add a **partial index** on frequently queried soft-deletable tables to avoid scanning deleted rows:

```sql
CREATE INDEX ix_threads_active ON forum.threads (id) WHERE deleted_at IS NULL;
```

- Soft delete is an `UPDATE`, not a `DELETE`:

```sql
UPDATE forum.threads SET deleted_at = now() WHERE id = :id AND deleted_at IS NULL;
```

- For cascading soft deletes (e.g. deleting a thread soft-deletes its posts), handle the cascade
  in application code — PostgreSQL `ON DELETE CASCADE` does not fire for `UPDATE` statements.
- Periodically hard-delete ancient soft-deleted rows (e.g. older than 1 year) via a scheduled job
  to prevent table bloat.

---

See [references/POSTGRES-TYPES.md](references/POSTGRES-TYPES.md) for PostgreSQL-specific types (jsonb, enums, arrays, ranges) and [references/INDEXING.md](references/INDEXING.md) for advanced indexing patterns.
