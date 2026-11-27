///|
extern "js" fn js_fs_read_text_opt(path : String) -> String? =
  #| (p) => {
  #|   const fs = require("node:fs");
  #|   try { return fs.readFileSync(p, "utf8"); } catch { return undefined; }
  #| }

///|
extern "js" fn js_fs_write_text_ok(path : String, content : String) -> Bool =
  #| (p, c) => {
  #|   const fs = require("node:fs");
  #|   try { fs.writeFileSync(p, c, "utf8"); return true; } catch { return false; }
  #| }

///|
async fn read_file_text(path : String) -> String {
  @async.pause()
  match js_fs_read_text_opt(path) {
    Some(s) => s
    None => fail("failed to read file: \{path}")
  }
}

///|
async fn write_file_text(path : String, content : String) -> Unit {
  @async.pause()
  if !js_fs_write_text_ok(path, content) {
    fail("failed to write file: \{path}")
  }
}
