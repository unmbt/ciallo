name = "unmbt/ciallo-security"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [
  "security",
  "jwt",
  "paseto",
  "argon2",
  "cors",
  "csrf",
  "rbac",
  "ciallo",
]

description = "Pure MoonBit CORS, CSRF, Helmet, JWT (HS256), PASETO v4.local, Argon2id/PBKDF2 password hashing, and RBAC/ABAC guards for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
}
