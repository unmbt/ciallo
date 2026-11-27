---
name: ciallo-driver-d1
description: Use when connecting unmbt/ciallo-orm to Cloudflare D1 on the JS target.
---

# unmbt/ciallo-driver-d1

## Rules
- Targets `--target js` only; wrap the Cloudflare Workers `env.DB` binding via `D1Driver::D1Driver(db)` and pass into `@orm.Db::Db(driver)`.
- Uses `Sqlite` dialect (`?` placeholders) and maps D1 unique/FK constraint errors into `@ciallo_data/codec.DataError`.
