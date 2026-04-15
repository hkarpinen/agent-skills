# PostgreSQL-Specific Types

## jsonb

Use `jsonb` for structured data where the shape is volatile or genuinely schema-less. Do not use it to avoid modelling.

```sql
-- Domain events: payload shape varies by event type
CREATE TABLE audit.domain_events (
    id           uuid         NOT NULL,
    event_type   text         NOT NULL,
    payload      jsonb        NOT NULL,
    occurred_at  timestamptz  NOT NULL,
    CONSTRAINT pk_domain_events PRIMARY KEY (id)
);

-- GIN index on a frequently queried jsonb field
CREATE INDEX ix_domain_events_order_id
    ON audit.domain_events ((payload->>'order_id'))
    WHERE event_type = 'OrderConfirmed';
```

## Enums

Use PostgreSQL enums for domain status values that are known at design time and change rarely.

```sql
CREATE TYPE orders.order_status AS ENUM (
    'draft',
    'pending',
    'confirmed',
    'shipped',
    'cancelled'
);

CREATE TABLE orders.orders (
    id      uuid                 NOT NULL,
    status  orders.order_status  NOT NULL  DEFAULT 'draft',
    CONSTRAINT pk_orders PRIMARY KEY (id)
);
```

If the value set changes frequently, use `text` with a check constraint instead — altering an enum type requires a schema migration.

## Arrays

Use arrays for small, bounded, homogeneous sets that are always read and written with the parent row.

```sql
-- Tags: simple string set, always accessed with the product
tags  text[]  NOT NULL  DEFAULT '{}',

-- GIN index for array membership queries
CREATE INDEX ix_products_tags ON catalog.products USING gin(tags);
```

Do not use arrays as a substitute for a related table when elements need their own identity or are queried individually.

## Ranges

Use range types (`daterange`, `tstzrange`, `numrange`) for interval data where overlap queries or exclusion constraints are needed.

```sql
-- Price periods: no overlapping periods for the same product
CREATE TABLE billing.price_periods (
    id            uuid          NOT NULL,
    product_id    uuid          NOT NULL,
    price         numeric(19,4) NOT NULL,
    valid_during  daterange     NOT NULL,
    CONSTRAINT pk_price_periods PRIMARY KEY (id),
    CONSTRAINT uq_price_periods_no_overlap
        EXCLUDE USING gist (product_id WITH =, valid_during WITH &&)
);
```
