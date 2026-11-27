# unmbt/ciallo-queue

Cloud-edge isomorphic `JobQueue` and `Scheduler` for `unmbt/ciallo`:
- `MemoryJobQueue` (delayed jobs, retries, idempotency, DLQ)
- `RedisJobQueue` (backed by `unmbt/ciallo-redis`)
- `OutboxQueue` (Transactional Outbox over `unmbt/ciallo-orm` `DbTx` — zero messages leaked on rollback)
- `Scheduler` (`CronExpr`) + Cloudflare Queues & Cron Triggers bridges
