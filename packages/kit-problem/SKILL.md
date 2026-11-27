---
name: ciallo-problem
description: Use when constructing RFC 9457 Problem Details responses with #callsite causal error chains in unmbt/ciallo.
---

# unmbt/ciallo-problem

## Key APIs
- `ProblemBuilder::ProblemBuilder(status~, code~, detail?)` + `.with_cause(code~, message~)` + `.with_extension(k, v)`.
- `.build(debug~)` / `.to_response(debug~)` automatically strips `source_loc` and causal `chain` when `debug=false`.
