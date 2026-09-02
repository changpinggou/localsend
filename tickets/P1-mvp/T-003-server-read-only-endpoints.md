# T-003: Server 只读 REST 端点（roots / list / download）

> Phase: P1 — MVP
> Priority: P0
> Estimate: 3d
> Dependencies: T-001、T-002、T-004、T-005
> Spec: REQUIREMENTS.md §3.2.2、§7 AC-1/AC-5
> Owner: Server

## 1. Background

P1 MVP 要求挂载端在 TLS 通道上暴露 3 个只读端点，让移动端能列出挂载点、浏览目录、流式下载文件。这 3 个端点不涉及写操作，但是后续 P2/P3 端点（mkdir/upload/move/delete）的样板基础。

## 2. Goal

在 `packages/core/src/fs/rest.rs` 内实现 3 个 handler，全部挂在 `/api/localsend/v2/fs` 前缀下，并接入现有的 `http::server` 路由管线。返回统一 JSON 错误结构。

## 3. Scope

### In scope
- `GET /roots` — 列出白名单
- `GET /list?path=&page=&size=&sort=` — 列出目录内容，分页
- `GET /download?path=` — 流式下载，必须支持 HTTP 206 Range
- 统一错误响应：`{ "error": { "code": "...", "message": "..." } }`，HTTP 状态码遵循 RFC

### Out of scope
- 写操作（→ T-010、T-014）
- 缩略图（→ T-021）
- 热插拔推送（→ T-019）
- 鉴权层（复用现有 TLS + 客户端证书，T-005 负责）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/rest.rs` | implement 3 handlers |
| `packages/core/src/fs/mod.rs` | 暴露 `pub fn register(state: &ServerStateV2, router: &mut Router)` |
| `packages/core/src/http/server/mod.rs` | modify：在 `start_with_port` 中调用 `fs::register` |
| `packages/core/src/fs/tests/rest_test.rs` | new |

## 5. Design

### 5.1 Handler 签名

```rust
async fn handle_roots(
    State(state): State<Arc<FsState>>,
) -> Result<Json<RootsResponse>, FsError>;

#[derive(Serialize)]
struct RootsResponse { roots: Vec<FsRoot> }

async fn handle_list(
    State(state): State<Arc<FsState>>,
    Query(params): Query<ListParams>,
) -> Result<Json<ListResponse>, FsError>;

#[derive(Deserialize)]
struct ListParams {
    path: String,
    #[serde(default)]
    page: usize,
    #[serde(default = "default_size")]
    size: usize,                     // 默认 100
    #[serde(default = "default_sort")]
    sort: String,                     // "name_asc" / "name_desc" / "size_asc" / "size_desc" / "mtime_desc"
}

async fn handle_download(
    State(state): State<Arc<FsState>>,
    Query(params): Query<DownloadParams>,
    headers: HeaderMap,
) -> Result<Response, FsError>;
```

### 5.2 ListResponse

```rust
#[derive(Serialize)]
struct ListResponse {
    entries: Vec<FsEntry>,
    total: usize,
    has_more: bool,
}

#[derive(Serialize)]
struct FsEntry {
    name: String,
    is_dir: bool,
    size: u64,
    mtime: i64,                       // unix epoch
    mime: Option<String>,
}
```

### 5.3 Range 下载

```rust
fn parse_range(header: Option<&str>, file_size: u64) -> Option<(u64, u64)>;  // (start, end inclusive)
```

- 无 Range 头 → `200 OK` + 整文件 + `Accept-Ranges: bytes`
- 有合法 Range → `206 Partial Content` + `Content-Range: bytes start-end/total`
- 越界 → `416 Range Not Satisfiable`
- 媒体类型优先按 `mime_guess` 推断，缺省 `application/octet-stream`

### 5.4 错误码

| HTTP | code | 含义 |
|------|------|------|
| 400  | `bad_request`     | 参数缺失或格式错 |
| 403  | `path_denied`     | 路径越权（F-S-5/6/7 三道防线触发） |
| 404  | `not_found`       | 路径不存在 |
| 413  | `too_large`       | 仅上传用 |
| 416  | `range_not_satisfiable` | Range 越界 |
| 500  | `internal`        | 其他服务端错误 |

每条错误都触发 `tracing::warn!(event = "fs.api.error", code, path, fingerprint)`（N-SEC-5 审计基础）。

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元

- `roots_returns_whitelist_only` — `FsConfig { whitelist: [] }` → 空数组
- `roots_excludes_non_whitelisted`
- `list_paginates_50`
- `list_rejects_path_outside_whitelist` → 403
- `list_rejects_dotdot` → 403
- `download_returns_200_no_range`
- `download_returns_206_with_range`
- `download_returns_416_invalid_range`
- `download_streams_large_file` — 100 MB 临时文件，验证只读一部分不爆内存

### Integration

`cargo test -p localsend --features full fs::tests::rest_test`

## 8. Acceptance criteria

- [ ] 3 个端点全部实现并通过单测
- [ ] Range 支持覆盖 0% / 50% / 99% 三种边界
- [ ] 错误响应体符合 §5.4 schema
- [ ] 全部 handler 经过 `path::PathGuard::check`（T-004）
- [ ] 性能基线：本地 SSD 1000 项目录 P95 ≤ 300 ms（手动脚本记录）

## 9. Risks / Notes

- **必须**先实现 T-004 path safety；本工单不重复安全判定
- Range 实现注意 `Content-Length` 与 `Content-Range` 的差异
- `mime_guess` 体积不大，但仅在 download 路径用，不要放到 `core` 的 `http` 模块
