///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror RuntimeError {
  Unavailable(String)
  IoFailure(String)
  Timeout(String)
}

///|
let next_key_id : Ref[Int32] = { val: 1, }

///|
/// 零反射、零 unsafe 强类型上下文键（支持在定义 Key 时绑定 ctx.require 缺失状态码，如鉴权 401、租户头 400）
pub struct ContextKey[T] {
  priv id : Int32
  priv name : String
  priv missing_status : Int32
  priv missing_detail : String?
  priv slot : Ref[T?]
}

///|
pub fn[T] ContextKey::ContextKey(
  name : String,
  missing_status~ : Int32 = 401,
  missing_detail? : String,
) -> ContextKey[T] {
  let id = next_key_id.val
  next_key_id.val = id + 1
  { id, name, missing_status, missing_detail, slot: { val: None, }, }
}

///|
pub fn[T] ContextKey::new(
  name : String,
  missing_status~ : Int32 = 401,
  missing_detail? : String,
) -> ContextKey[T] {
  ContextKey::ContextKey(name, missing_status~, missing_detail?)
}

///|
pub fn[T] ContextKey::name(self : ContextKey[T]) -> String {
  self.name
}

///|
pub fn[T] ContextKey::missing_status(self : ContextKey[T]) -> Int32 {
  self.missing_status
}

///|
pub fn[T] ContextKey::missing_detail(self : ContextKey[T]) -> String? {
  self.missing_detail
}

///|
priv struct ErasedEntry {
  key_name : String
  project : () -> Unit
}

///|
/// 内部类型擦除存储容器（供 Env、Context 与 App providers 复用，零反射且读后立即清槽防 GC 泄漏）
pub struct ContextStore {
  priv entries : Map[Int32, ErasedEntry]
}

///|
pub fn ContextStore::ContextStore() -> ContextStore {
  { entries: Map([]), }
}

///|
pub fn[T] ContextStore::set(
  self : ContextStore,
  key : ContextKey[T],
  value : T,
) -> Unit {
  let slot = key.slot
  self.entries[key.id] = {
    key_name: key.name,
    project: () => slot.val = Some(value),
  }
}

///|
pub fn[T] ContextStore::get(self : ContextStore, key : ContextKey[T]) -> T? {
  match self.entries.get(key.id) {
    None => None
    Some(entry) => {
      key.slot.val = None
      (entry.project)()
      let out = key.slot.val
      key.slot.val = None
      out
    }
  }
}

///|
pub fn[T] ContextStore::contains(
  self : ContextStore,
  key : ContextKey[T],
) -> Bool {
  self.entries.contains(key.id)
}

///|
pub fn ContextStore::clone(self : ContextStore) -> ContextStore {
  let copied : Map[Int32, ErasedEntry] = Map([])
  self.entries.each((k, v) => copied[k] = v)
  { entries: copied, }
}

///|
/// 合并另一个容器；若检测到重复键且 allow_override=false，返回冲突键名
pub fn ContextStore::merge_from(
  self : ContextStore,
  other : ContextStore,
  allow_override~ : Bool = false,
) -> String? {
  let mut conflict : String? = None
  other.entries.each((k, v) => {
    if conflict is None {
      if !allow_override && self.entries.contains(k) {
        conflict = Some(v.key_name)
      } else {
        self.entries[k] = v
      }
    }
  })
  conflict
}

///|
/// 组装期环境变量与宿主绑定构建器（构建完成后生成运行期纯只读 Env，根除 Native 多协程跨请求状态污染）
pub struct EnvBuilder {
  priv vars : Map[String, String]
  priv bindings : ContextStore
}

///|
pub fn EnvBuilder::EnvBuilder(
  vars~ : Map[String, String] = Map([]),
) -> EnvBuilder {
  let copied : Map[String, String] = Map([])
  vars.each((k, v) => copied[k] = v)
  { vars: copied, bindings: ContextStore::ContextStore(), }
}

///|
pub fn EnvBuilder::set_var(
  self : EnvBuilder,
  key : StringView,
  value : StringView,
) -> EnvBuilder {
  self.vars[key.to_owned()] = value.to_owned()
  self
}

///|
pub fn[T] EnvBuilder::bind(
  self : EnvBuilder,
  key : ContextKey[T],
  value : T,
) -> EnvBuilder {
  self.bindings.set(key, value)
  self
}

///|
pub fn EnvBuilder::build(self : EnvBuilder) -> Env {
  let copied : Map[String, String] = Map([])
  self.vars.each((k, v) => copied[k] = v)
  { vars: copied, bindings: self.bindings.clone(), }
}

///|
/// 运行期纯只读环境变量与宿主绑定容器（Native 启动构建一次零拷贝共享，JS Workers 按请求零开销包装宿主 env）
pub struct Env {
  priv vars : Map[String, String]
  priv bindings : ContextStore
}

///|
pub fn Env::Env(vars~ : Map[String, String] = Map([])) -> Env {
  let copied : Map[String, String] = Map([])
  vars.each((k, v) => copied[k] = v)
  { vars: copied, bindings: ContextStore::ContextStore(), }
}

///|
pub fn Env::get_var(self : Env, key : StringView) -> String? {
  self.vars.get(key.to_owned())
}

///|
pub fn Env::require_var(
  self : Env,
  key : StringView,
) -> String raise RuntimeError {
  let k = key.to_owned()
  match self.vars.get(k) {
    Some(v) => v
    None =>
      raise RuntimeError::Unavailable("missing environment variable: \{k}")
  }
}

///|
pub fn[T] Env::get_binding(self : Env, key : ContextKey[T]) -> T? {
  self.bindings.get(key)
}

///|
/// 纯函数式派生包含新绑定的只读 Env（绝不修改原 Env 实例，供适配器按连接安全注入 remote_addr_key）
pub fn[T] Env::with_binding(self : Env, key : ContextKey[T], value : T) -> Env {
  let next_bindings = self.bindings.clone()
  next_bindings.set(key, value)
  { vars: self.vars, bindings: next_bindings, }
}

///|
/// 请求级异步任务托管上下文（Native 走任务组收尾，JS Workers 透传 ctx.waitUntil）
pub struct ExecutionContext {
  priv schedule_fn : ((async () -> Unit) -> Unit)?
  priv pending : Array[async () -> Unit]
}

///|
pub fn ExecutionContext::ExecutionContext(
  schedule_fn? : (async () -> Unit) -> Unit,
) -> ExecutionContext {
  { schedule_fn, pending: [], }
}

///|
pub fn ExecutionContext::has_scheduler(self : ExecutionContext) -> Bool {
  self.schedule_fn is Some(_)
}

///|
pub fn ExecutionContext::wait_until(
  self : ExecutionContext,
  task : async () -> Unit,
) -> Unit {
  match self.schedule_fn {
    Some(scheduler) => scheduler(task)
    None => self.pending.push(task)
  }
}

///|
pub async fn ExecutionContext::drain_background(
  self : ExecutionContext,
) -> Unit {
  while !self.pending.is_empty() {
    let batch = self.pending.copy()
    self.pending.clear()
    @async.with_task_group(group => {
      for task in batch {
        group.spawn_bg(allow_failure=true, () => task())
      }
    })
  }
}

///|
/// 可移植键值存储抽象
pub(open) trait KvStore {
  async fn get(Self, key : StringView) -> String? raise RuntimeError
  async fn put(Self, key : StringView, value : StringView, ttl_sec? : Int32) -> Unit raise RuntimeError
  async fn delete(Self, key : StringView) -> Unit raise RuntimeError
}

///|
/// 可移植出站 HTTP 客户端抽象
pub(open) trait HttpClient {
  async fn send(Self, req : @http.Request) -> @http.Response raise RuntimeError
}

///|
/// 可移植单调/墙钟微秒与毫秒时钟抽象（真实时间戳保留 Int64）
pub(open) trait Clock {
  fn now_micros(Self) -> Int64
  fn now_ms(Self) -> Int64 = _
}

///|
impl Clock with fn now_ms(self : Self) -> Int64 {
  self.now_micros() / 1000L
}

///|
/// 统一拓扑启停生命周期契约（Native 收到 SIGTERM 按依赖逆序优雅释放；Workers 模式可被 Tree-shake）
pub(open) trait Lifecycle {
  fn lifecycle_name(Self) -> String
  async fn on_start(Self) -> Unit
  async fn on_stop(Self) -> Unit
}

///|
/// 标准就绪探针契约（供 CapabilityBundle 注册与 ciallo-actuator /readyz 并行聚合）
#derive(Debug, Eq, ToJson)
pub(all) struct HealthStatus {
  name : String
  ok : Bool
  detail : String?
  elapsed_micros : Int64
}

///|
pub extend HealthStatus with ToJson::{to_json}

///|
pub(open) trait HealthCheck {
  fn check_name(Self) -> String
  async fn check(Self) -> HealthStatus
}

///|
/// W3C Trace Context (traceparent / tracestate) 全链路贯通上下文
#derive(Debug, Eq)
pub(all) struct TraceContext {
  trace_id : String
  span_id : String
  parent_span_id : String?
  sampled : Bool
  tracestate : String?
}

///|
fn is_lower_hex(s : StringView) -> Bool {
  for ch in s {
    let c = ch.to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
fn is_all_zero(s : StringView) -> Bool {
  for ch in s {
    if ch != '0' {
      return false
    }
  }
  true
}

///|
fn hex_nibble(n : Int32) -> Char {
  match n & 0xF {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    _ => 'f'
  }
}

///|
fn u64_to_hex16(v : UInt64) -> String {
  let sb = StringBuilder()
  let mut i = 15
  while i >= 0 {
    let shift = i * 4
    let nib = ((v >> shift) & 0xFUL).to_int()
    sb.write_char(hex_nibble(nib))
    i = i - 1
  }
  sb.to_string()
}

///|
let trace_seq : Ref[UInt64] = { val: 1UL, }

///|
fn next_id_u64(clock : &Clock) -> UInt64 {
  let seq = trace_seq.val
  trace_seq.val = seq + 1UL
  let t = clock.now_micros().reinterpret_as_uint64()
  // SplitMix64 mixing for non-zero well-distributed 64-bit IDs
  let mut x = (t ^ (seq * 0x9e3779b97f4a7c15UL)) + 0x9e3779b97f4a7c15UL
  x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9UL
  x = (x ^ (x >> 27)) * 0x94d049bb133111ebUL
  x = x ^ (x >> 31)
  if x == 0UL {
    1UL
  } else {
    x
  }
}

///|
fn hex_byte_val(ch : Char) -> Int32 {
  let c = ch.to_int()
  if c >= 48 && c <= 57 {
    c - 48
  } else {
    c - 87
  }
}

///|
pub fn parse_traceparent(header : StringView) -> TraceContext? {
  let s = header.trim().to_owned()
  if s.length() != 55 {
    return None
  }
  if s.code_unit_at(2) != '-' ||
    s.code_unit_at(35) != '-' ||
    s.code_unit_at(52) != '-' {
    return None
  }
  let version = s[:2]
  let trace_id = s[3:35]
  let span_id = s[36:52]
  let flags = s[53:55]
  if !is_lower_hex(version) ||
    !is_lower_hex(trace_id) ||
    !is_lower_hex(span_id) ||
    !is_lower_hex(flags) {
    return None
  }
  if version.to_owned() == "ff" {
    return None
  }
  if is_all_zero(trace_id) || is_all_zero(span_id) {
    return None
  }
  let flag_val = (hex_byte_val(flags.code_unit_at(0).unsafe_to_char()) << 4) |
    hex_byte_val(flags.code_unit_at(1).unsafe_to_char())
  let sampled = (flag_val & 1) == 1
  Some({
    trace_id: trace_id.to_owned(),
    span_id: span_id.to_owned(),
    parent_span_id: None,
    sampled,
    tracestate: None,
  })
}

///|
pub fn TraceContext::to_traceparent(self : TraceContext) -> String {
  let flags = if self.sampled { "01" } else { "00" }
  "00-\{self.trace_id}-\{self.span_id}-\{flags}"
}

///|
pub fn TraceContext::new_root(clock : &Clock) -> TraceContext {
  let hi = u64_to_hex16(next_id_u64(clock))
  let lo = u64_to_hex16(next_id_u64(clock))
  let span = u64_to_hex16(next_id_u64(clock))
  {
    trace_id: "\{hi}\{lo}",
    span_id: span,
    parent_span_id: None,
    sampled: true,
    tracestate: None,
  }
}

///|
pub fn TraceContext::child_span(
  self : TraceContext,
  clock : &Clock,
) -> TraceContext {
  {
    trace_id: self.trace_id,
    span_id: u64_to_hex16(next_id_u64(clock)),
    parent_span_id: Some(self.span_id),
    sampled: self.sampled,
    tracestate: self.tracestate,
  }
}

///|
pub struct MemoryKv {
  priv data : Map[String, String]
}

///|
pub fn MemoryKv::MemoryKv() -> MemoryKv {
  { data: Map([]), }
}

///|
pub impl KvStore for MemoryKv with fn get(self, key) -> String? raise RuntimeError {
  @async.pause()
  self.data.get(key.to_owned())
}

///|
pub impl KvStore for MemoryKv with fn put(self, key, value, ttl_sec?) -> Unit raise RuntimeError {
  ignore(ttl_sec)
  @async.pause()
  self.data[key.to_owned()] = value.to_owned()
}

///|
pub impl KvStore for MemoryKv with fn delete(self, key) -> Unit raise RuntimeError {
  @async.pause()
  self.data.remove(key.to_owned())
}

///|
pub struct MockHttpClient {
  priv handler : async (@http.Request) -> @http.Response raise RuntimeError
}

///|
pub fn MockHttpClient::MockHttpClient(
  handler : async (@http.Request) -> @http.Response raise RuntimeError,
) -> MockHttpClient {
  { handler, }
}

///|
pub impl HttpClient for MockHttpClient with fn send(self, req) -> @http.Response raise RuntimeError {
  (self.handler)(req)
}

///|
pub struct FixedClock {
  priv mut current_micros : Int64
  priv step_micros : Int64
}

///|
pub fn FixedClock::FixedClock(
  start_micros~ : Int64 = 0L,
  step_micros~ : Int64 = 0L,
) -> FixedClock {
  { current_micros: start_micros, step_micros, }
}

///|
pub fn FixedClock::advance(self : FixedClock, delta_micros : Int64) -> Unit {
  self.current_micros = self.current_micros + delta_micros
}

///|
pub impl Clock for FixedClock with fn now_micros(self) -> Int64 {
  let out = self.current_micros
  self.current_micros = out + self.step_micros
  out
}
