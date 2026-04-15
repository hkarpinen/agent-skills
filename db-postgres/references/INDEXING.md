# Advanced Indexing Patterns

## Index Types

| Use case | Type |
|---|---|
| Equality and range queries (default) | B-tree |
| `jsonb` field queries | GIN |
| Array membership (`@>`, `&&`) | GIN |
| Full-text search | GIN on `tsvector` |
| Range overlap, geometric | GiST |

## Partial Indexes

Index only the subset of rows that matter for common queries.

```sql
-- Partial index: only active orders (avoids indexing historical data)
CREATE INDEX ix_orders_customer_active
    ON orders.orders (customer_id)
    WHERE status NOT IN ('shipped', 'cancelled');

-- Soft delete pattern
CREATE INDEX ix_orders_active
    ON orders.orders (customer_id, created_at)
    WHERE deleted_at IS NULL;
```

## Covering Indexes

Include columns to satisfy queries from the index alone, avoiding heap lookups.

```sql
-- Covering index: include columns for index-only scan
CREATE INDEX ix_orders_customer_covering
    ON orders.orders (customer_id)
    INCLUDE (status, created_at);
```

## Composite Indexes

Order matters. Most selective column first, or match query pattern.

```sql
-- For: WHERE customer_id = ? AND status = ? ORDER BY created_at DESC
CREATE INDEX ix_orders_customer_status_created
    ON orders.orders (customer_id, status, created_at DESC);
```

## Foreign Key Indexes

PostgreSQL does not create FK indexes automatically. Every FK column needs an explicit index.

```sql
CREATE INDEX ix_order_lines_order_id   ON orders.order_lines (order_id);
CREATE INDEX ix_order_lines_product_id ON orders.order_lines (product_id);
```

## Soft Deletes

```sql
-- View for application queries
CREATE VIEW orders.active_orders AS
    SELECT * FROM orders.orders
    WHERE deleted_at IS NULL;
```

## Security and Permissions

The application runtime user should not own schema objects.

```sql
-- Migration/CI user owns the schema
GRANT ALL ON SCHEMA orders TO migration_user;

-- Application runtime user: DML only, no DDL
GRANT USAGE ON SCHEMA orders TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA orders TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA orders
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
```
