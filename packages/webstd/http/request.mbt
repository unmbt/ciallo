///|
pub(all) struct Request {
  meth : Method
  url : @url.Url
  headers : Headers
  body : Body
}

///|
pub fn Request::Request(
  meth~ : Method,
  url~ : StringView,
  headers~ : Headers = Headers::Headers(),
  body~ : Body = Body::Empty,
) -> Request raise @url.UrlError {
  { meth, url: @url.Url::parse(url), headers, body, }
}

///|
pub fn Request::header(self : Request, name : StringView) -> String? {
  self.headers.get(name)
}
