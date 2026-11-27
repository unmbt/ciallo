///|
fn html_escape(input : String) -> String {
  let sb = StringBuilder()
  for ch in input {
    match ch {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      '\'' => sb.write_string("&#39;")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// 生成内置 Scalar 交互式 API 文档 HTML（支持内网离线替换 script_url 与 custom_css，注入属性严格 HTML 转义防 XSS）
pub fn scalar_html(
  title~ : String,
  spec_url~ : String = "/openapi.json",
  script_url~ : String = "https://cdn.jsdelivr.net/npm/@scalar/api-reference",
  custom_css? : String,
) -> String {
  let safe_title = html_escape(title)
  let safe_spec_url = html_escape(spec_url)
  let safe_script_url = html_escape(script_url)
  let style_block = match custom_css {
    Some(css) => {
      // Prevent breaking out of <style> tag
      let safe_css = html_escape(css)
      "\n  <style>\{safe_css}</style>"
    }
    None => ""
  }
  "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n  <title>\{safe_title}</title>\{style_block}\n</head>\n<body>\n  <script id=\"api-reference\" data-url=\"\{safe_spec_url}\"></script>\n  <script src=\"\{safe_script_url}\"></script>\n</body>\n</html>\n"
}
