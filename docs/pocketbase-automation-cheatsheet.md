# PocketBase Automation Cheatsheet

## Quick Positioning

- Use PocketBase-first when the problem is stateful: products, prices, stocks, warehouses, mappings, sync history.
- Use n8n-first when the problem is mostly glue logic between SaaS systems.
- Use PocketBase plus worker when sync complexity is medium or high.
- Use PocketBase plus n8n when PocketBase should own truth but external orchestration should stay fast.

## Minimal Collections

1. `integration_sources`
2. `jobs`
3. `sync_runs`
4. `sync_item_results`
5. `products`
6. `feed_exports`

## Standard Job Statuses

- `pending`
- `processing`
- `done`
- `failed`
- `retry`
- `cancelled`

## Standard Sync Run Statuses

- `running`
- `success`
- `partial`
- `failed`

## Recommended Split

- Hooks: validate, enqueue, lightweight reactions.
- Crons: schedule jobs and recover stuck work.
- Workers: heavy imports, price sync, stock sync, feed generation, retry.
- n8n: external webhook, CRM, notifications, SaaS glue.

## Default Flows

### Price and stock sync

1. Create job.
2. Claim job in worker.
3. Create sync run.
4. Fetch source data.
5. Update SKU by SKU.
6. Write item-level results.
7. Mark run as success, partial, or failed.
8. Retry only failed items if needed.

### Feed generation

1. Create `build_feed` job.
2. Load active products.
3. Validate required fields.
4. Skip or fail bad items with reasons.
5. Write feed artifact.
6. Save `feed_exports` metadata.

### Supplier import with staging

1. Fetch raw source.
2. Save staging records if source quality is poor.
3. Normalize into internal schema.
4. Apply to products.
5. Build feed or push downstream.

## Use PocketBase Over n8n When

- you need SKU-level error tracking
- you need auditability
- you need replay or retry by item
- you need mapping tables
- you need a real source of truth for sync state
- the workflow is effectively an integration backend

## Use n8n Over PocketBase When

- the flow is simple and event-driven
- there are many external connectors
- visibility as a visual workflow matters
- data state is secondary to orchestration speed

## Red Flags

- all business logic lives inside n8n nodes
- no persistent sync state exists
- no item-level failure tracking exists
- heavy jobs run only in hooks
- dirty supplier data goes straight to target
- no replay strategy exists

## Practical Recommendation

- Small project: PocketBase-only can be enough.
- Production catalog sync: PocketBase plus worker.
- Catalog sync plus many external automations: PocketBase plus worker plus n8n.
- Avoid n8n-only when the core business problem is prices, stocks, feeds, and reliability.