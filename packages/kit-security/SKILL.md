---
name: ciallo-security
description: Use when adding CORS, Helmet, CSRF, JWT (HS256), PASETO v4.local, Argon2id/PBKDF2 password hashing, or RBAC/ABAC route guards to a ciallo App.
---

# unmbt/ciallo-security

## Key APIs
- `sign_jwt_hs256` / `verify_jwt_hs256` and `paseto_v4_encrypt` / `paseto_v4_decrypt`.
- `Argon2idHasher` & `Pbkdf2Hasher` (`PasswordHasher` trait).
- `mount_cors`, `HelmetBundle`, `CsrfBundle`, `jwt_auth_guard`, `require_roles`, `require_any_role`, `require_policy`.
