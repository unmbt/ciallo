# ADR-013：严格统一规范类型拼写（废除旧拼写双拼写兼容）与 `HttpError` 构造器集补全

- 状态：Accepted
- 日期：2026-11-27
- 关联：`REQ-CONTRACT-01`、`REQ-GEN-01`、`REQ-WORK-01`
- 关系：修订 [ADR-012](012-int32-nullable-cancel-safety-and-v01-slimming.md) 第 1 节第 2 条，并同步对齐 [architecture-and-contracts.md](../spec/architecture-and-contracts.md) 第 3.6 节 `HttpError` 辅助构造器契约。

## 背景

1. 在 MoonBit `v1.0.0-rc1` 中，`moon fmt` 与 `moon fix` 已将整型与可选类型统一规范为 **`Int32`**、**`UInt32`** 与后缀 **`T?`**。原 ADR-012 允许 `ciallo-gen` 双拼写兼容旧写法 `Int` / `UInt` 与显式 `Option[T]`，反而会纵容未格式化的过时代码进入项目、增加 AST 扫描器分支复杂度并制造风格割裂。
2. ADR-012 正文提及为 `HttpError` 全部 11 个常用构造场景配备 `#callsite(autofill(loc))` 辅助函数，但 `architecture-and-contracts.md` 第 3.6 节仅列出了其中 8 个，遗漏了 `method_not_allowed`、`payload_too_large` 与 `unsupported_media_type`。

## 决策

1. **`ciallo-gen` 严禁兼容旧类型拼写，统一只接受 `moon fmt` / `moon fix` 规范拼写**：
   - `ciallo-gen schema` 仅将 **`Int32`**、**`UInt32`** 识别为 32 位有符号/无符号整型，仅将后缀 **`T?`** 识别为结构体可选字段包装；
   - 当源码中出现旧写法 `Int`、`UInt` 或 `Option[T]` 时，`ciallo-gen` 不做静默兼容，直接输出带文件名与源码行号的明确诊断错误，引导开发者先运行 `moon fmt` / `moon fix` 规范化后再生成代码；
   - 全仓文档（`AGENTS.md`、`README.mbt.md`、`docs/README.md`、`docs/spec/*.md`）同步移除双拼写兼容表述。
2. **补齐 `HttpError` 全部 11 个 `#callsite(autofill(loc))` 构造辅助函数**：
   - 在 `unmbt/ciallo/core` 中完整提供：`bad_request`、`unauthorized`、`forbidden`、`not_found`、`method_not_allowed`、`payload_too_large`、`unsupported_media_type`、`unprocessable`、`too_many_requests`、`internal`、`custom`。

## 后果

- 全仓代码风格、生成器输入契约与 `moon fmt --check` 100% 统一，无历史旧拼写包袱；
- 业务代码及框架内部均可对全部 HTTP 常见错误通过 `#callsite(autofill(loc))` 自动采集精准 `SourceLoc`。
