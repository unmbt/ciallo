name = "unmbt/ciallo-queue"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [
  "queue",
  "outbox",
  "cron",
  "scheduler",
  "cloudflare-queues",
  "ciallo",
]

description = "Cloud-edge isomorphic JobQueue and Cron Scheduler (Memory, Redis, ORM Transactional Outbox, and Cloudflare Queues/Cron Triggers) for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
  "unmbt/ciallo-data@0.1.0",
  "unmbt/ciallo-orm@0.1.0",
  "unmbt/ciallo-redis@0.1.0",
}
