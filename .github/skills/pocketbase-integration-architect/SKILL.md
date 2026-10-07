---
name: pocketbase-integration-architect
description: "Use when: designing automation for PocketBase, comparing PocketBase vs n8n, modeling jobs and sync statuses, planning price sync, stock sync, product feeds, YML generation, supplier imports, 1C or MoySklad integrations, retries, item-level errors, and hybrid PocketBase plus n8n architectures."
---

# PocketBase Integration Architect

## Purpose

Use this skill when the user is designing an automation or integration system where PocketBase may act as the domain backend.

Typical problem areas:
- jobs and queues
- sync runs and sync statuses
- item-level error tracking
- product imports
- price synchronization
- stock synchronization
- YML or feed generation
- supplier imports
- 1C integrations
- MoySklad integrations
- hybrid PocketBase plus n8n architectures

This skill is not for trivial webhook chains. It is for integration systems with persistent data state, retries, partial failures, replay, and supportability concerns.

## Core Recommendation Model

Prefer PocketBase-first when:
- automation revolves around owned data
- product catalog state matters
- prices and stocks must stay auditable
- retries are required
- item-level failures matter
- the system needs sync history and operational visibility

Prefer n8n-first when:
- the problem is mostly glue logic between external services
- the main need is fast orchestration with many connectors
- the workflow is webhook, CRM, email, Telegram, callback, or lightweight API chaining

Prefer a hybrid design when:
- PocketBase should own domain state
- n8n would still reduce effort for external orchestration
- heavy business logic should not live inside workflow nodes

## Decision Heuristics

Choose PocketBase-first if the user mentions:
- product feeds
- YML
- stock sync
- price sync
- warehouses
- mappings
- supplier normalization
- 1C
- MoySklad
- catalog imports
- partial failures by SKU
- retry of failed items
- audit or sync history

Choose n8n-first if the user mentions:
- CRM handoff
- notifications
- forms
- webhook fan-out
- simple SaaS integrations
- fast MVP automation

Choose PocketBase plus worker if the user mentions:
- large catalogs
- heavy transformations
- frequent syncs
- long-running jobs
- many warehouses
- multiple price types
- repeatable partial failures
- need for deterministic retries

Choose PocketBase plus n8n if both are true:
- domain state must remain in PocketBase
- external orchestration is easier in n8n

## Recommended Data Model

Start from these collections unless the user already has a better verified structure.

### 1. integration_sources

Suggested fields:
- name
- type
- base_url
- credentials
- is_active
- sync_interval_minutes
- last_success_at
- last_error_at

### 2. jobs

Suggested fields:
- type
- source
- status
- priority
- payload
- scheduled_at
- started_at
- finished_at
- attempt
- max_attempts
- error_message

Standard statuses:
- pending
- processing
- done
- failed
- retry
- cancelled

### 3. sync_runs

Suggested fields:
- job
- source
- sync_type
- status
- started_at
- finished_at
- total_items
- processed_items
- success_items
- failed_items
- skipped_items
- meta

Standard statuses:
- running
- success
- partial
- failed

### 4. sync_item_results

Suggested fields:
- sync_run
- external_id
- sku
- status
- action
- message
- payload_hash
- before_data
- after_data

Standard statuses:
- success
- failed
- skipped

### 5. products

Suggested fields:
- sku
- source
- external_id
- name
- price
- stock
- attributes_json
- is_active
- last_synced_at

### 6. feed_exports

Suggested fields:
- type
- status
- generated_at
- file_path
- items_count
- error_message

## Recommended Processing Split

Prefer this split unless the task is truly tiny:

1. PocketBase collections store domain state.
2. Hooks validate, enqueue, or react to lightweight record events.
3. Crons schedule work and recover stuck jobs.
4. Worker processes perform heavy sync logic.
5. Optional n8n flows handle external SaaS glue and orchestration.

Avoid keeping all critical sync logic only inside hooks and cron callbacks.

## Common Architecture Patterns

### Pattern 1: Price and Stock Sync

Flow:
1. Cron creates a job.
2. Worker claims a pending job.
3. Worker creates a sync_run.
4. Source data is fetched.
5. Each SKU is validated and updated.
6. Item results are stored.
7. The run is marked success, partial, or failed.
8. Failed items may be retried with a dedicated job.

### Pattern 2: Feed Generation

Flow:
1. A build_feed job is created.
2. Worker loads active products.
3. Required fields are validated.
4. Invalid items are skipped or failed with reasons.
5. Output is written to a feed artifact.
6. feed_exports stores final metadata and status.

### Pattern 3: Supplier Import with Staging

Flow:
1. Raw data is fetched from the supplier.
2. Raw rows may be stored in a staging collection.
3. A normalization job transforms supplier format into internal format.
4. A product update job applies normalized data.
5. Optional feed export or KIT push runs afterward.

## Evaluation Checklist

When analyzing the user's problem, answer these questions:

1. What is the system of record?
2. Where should sync state live?
3. Is item-level retry needed?
4. Do we need SKU-level auditability?
5. Is the workload scheduled, event-driven, or both?
6. Are heavy transformations involved?
7. Are multiple warehouses or price types involved?
8. Does the user need visual orchestration for external systems?
9. Should PocketBase remain the operational source of truth?
10. Would a hybrid design reduce complexity without losing control?

## Output Contract

When using this skill, produce answers in this order:

1. Recommendation
State one of:
- PocketBase-first
- n8n-first
- PocketBase plus worker
- PocketBase plus n8n

2. Why
Explain in terms of:
- domain state
- reliability
- retries
- observability
- business-logic complexity
- integration surface

3. Concrete Architecture
Provide:
- collections
- statuses
- processing flow
- retry model
- worker split if needed
- n8n role if needed

4. Risks
State what could become fragile or expensive.

5. Next Step
End with the smallest concrete next design step.

## Anti-Patterns

Flag these as risky:
- all business logic inside n8n nodes
- no persistent sync status model
- no item-level error tracking
- direct dirty-source to target sync without staging
- heavy long-running jobs entirely inside PocketBase hooks
- no retry or replay strategy
- no separation between domain state and orchestration

## Recommendation Defaults

Recommend PocketBase-only when:
- the team wants a compact self-hosted backend
- integrations are moderate in number
- domain logic matters more than connector count

Recommend PocketBase plus worker when:
- sync complexity is medium or high
- catalogs are large
- cron and hooks alone would become fragile

Recommend PocketBase plus n8n when:
- there are many webhook or SaaS integrations
- PocketBase must still own sync truth

Recommend against n8n-only when:
- the core problem is inventory, catalog, pricing, mappings, or feed integrity
- item-level observability matters
- replay and operational control matter