///|
async fn read_file_text(path : String) -> String {
  @fs.read_text(path)
}

///|
async fn write_file_text(path : String, content : String) -> Unit {
  @fs.write_text(path, content, create_mode=@fs.CreateMode::CreateOrTruncate)
}
