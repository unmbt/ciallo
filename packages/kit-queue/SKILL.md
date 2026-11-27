---
name: ciallo-queue
description: Use when scheduling background jobs, Transactional Outbox messages inside ORM DbTx, Redis queues, Cron schedules, or Cloudflare Queues/Cron Triggers.
---

# unmbt/ciallo-queue

## Key APIs
- `JobQueue` trait (`MemoryJobQueue`, `RedisJobQueue`).
- `OutboxQueue::enqueue_in_tx(tx, queue~, payload~)` + `poll_and_dispatch(db, handler)` for transactional outbox guarantees.
- `Scheduler` + `CronExpr` + `dispatch_cf_queue_batch` / `dispatch_cf_cron`.
