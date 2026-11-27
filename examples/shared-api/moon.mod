name = "unmbt/ciallo-example-shared"

version = "0.1.0"

private = true

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
  "unmbt/ciallo-testing@0.1.0",
}

// 仓库内部自举（dogfooding）：使用 moonrun 直接执行工作区已编译的 ciallo-gen.wasm，避免嵌套调用 `moon run` 与父进程争抢根 _build/.moon-lock；
// 外部用户只需在自己的 moon.mod 将 command 替换为 "moonx unmbt/ciallo-gen/cmd/ciallo-gen@0.1.0 schema $input -o $output"，业务 moon.pkg 一字不差！
rule(
  name: "ciallo_schema",
  command: "moonrun ../../_build/wasm/debug/build/unmbt/ciallo-gen/cmd/ciallo-gen/ciallo-gen.wasm schema $input -o $output",
)
