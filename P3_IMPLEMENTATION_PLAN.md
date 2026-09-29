# P3-CRUD Implementation Plan

> Phase: P3 — CRUD
> Target tickets: T-014, T-015, T-016, T-017
> Estimated effort: 8 days

## Overview

P3 completes the CRUD operations for the LocalU filesystem feature:
- **T-014**: Server-side move/delete/stat endpoints
- **T-015**: Server-side audit logging + platform recycle bin
- **T-016**: Client-side mutation UI (rename/move/delete with multi-select)
- **T-017**: Client-side optimistic updates + broadcast

## Current State (P1/P2 Completed)

### Rust Core (`packages/core/src/fs/`)
- ✅ `config.rs` — FsConfig with whitelist, limits
- ✅ `mount.rs` — FsRoot, MountTable, FsMount
- ✅ `path.rs` — FsError, FsPath, PathGuard (sandbox)
- ✅ `rest.rs` — Read-only endpoints (roots/list/download)
- ✅ `upload.rs` — mkdir + session-based upload (init/chunk/finish/cancel)
- ✅ `events.rs` — FsEvent enum (RootsChanged, AuditLog, QuotaWarn)
- ✅ `mod.rs` — Module facade + feature gate

### FRB Bindings (`packages/localsend_isolates/rust/src/api/`)
- ✅ `model.rs` — FsRoot, FsEntry, ListResponse, RootsResponse mirrors
- ✅ `http.rs` — RsHttpClient with fs methods (list_roots, list_dir, download, fsMkdir, fsUpload*)

### Dart Side
- ✅ `fs_list_provider.dart` — Remote browsing state machine
- ✅ `fs_download_provider.dart` — Download + save flow
- ✅ `fs_upload_provider.dart` — Upload queue + session management
- ✅ `remote_browser_page.dart` — Basic browsing UI + upload menu
- ✅ Widgets: breadcrumb, list_view, grid_view, empty_state, sort_menu, view_mode_toggle, mkdir_dialog, upload_action_sheet, upload_queue_bar, file_action_sheet

## Implementation Order

Strict dependency chain:
1. **T-014** (server move/delete/stat) → no client dependency
2. **T-015** (audit + recycle) → depends on T-014 delete
3. **T-016** (client mutation UI) → depends on T-014 endpoints
4. **T-017** (optimistic updates) → depends on T-016

---

## T-014: Server move / delete / stat endpoints

### Files to Create/Modify

| File | Change |
|------|--------|
| `packages/core/src/fs/move_delete.rs` | **new** — move/delete business logic |
| `packages/core/src/fs/stat.rs` | **new** — stat endpoint handler |
| `packages/core/src/fs/rest.rs` | **modify** — register 3 new handlers |
| `packages/core/src/fs/mod.rs` | **modify** — pub use new modules |
| `packages/core/src/fs/tests/move_delete_test.rs` | **new** — unit tests |

### Design

#### move endpoint
```rust
POST /api/localsend/v2/fs/move
Body: { from: String, to: String, confirm: bool }
Response: { path: String }
```

- Both `from` and `to` go through `PathGuard::check`
- `confirm=false` → 400 BadRequest
- Try `tokio::fs::rename(from, to)` first
- On `EXDEV` (cross-device): fall back to `copy + delete`
- Copy mode: if fails mid-way, clean up target

#### delete endpoint
```rust
POST /api/localsend/v2/fs/delete
Body: { paths: Vec<String>, recycle: bool, confirm: bool }
Response: { deleted: Vec<String>, failed: Vec<DeleteFailure> }
```

- Each path goes through `PathGuard::check`
- `recycle=true` → call T-015 recycle (stub for now)
- `recycle=false` → `tokio::fs::remove_file` / `remove_dir_all`
- Partial failures aggregated into `failed` array

#### stat endpoint
```rust
GET /api/localsend/v2/fs/stat?path=<path>
Response: {
  name: String,
  is_dir: bool,
  size: u64,
  mtime: i64,
  mime: Option<String>,
  supports_range: bool,  // always true
  etag: String,          // mtime+size hash
}
```

- Single metadata fetch
- `etag` = hash(mtime + size) for resume validation

### Acceptance Criteria
- [ ] 3 endpoints implemented + unit tests
- [ ] Write operations require `confirm: true`
- [ ] Delete aggregates failures (single item doesn't block others)
- [ ] Move falls back to copy on cross-device
- [ ] stat.etag is consistent with upload session validation

---

## T-015: Server audit log + platform recycle bin

### Files to Create/Modify

| File | Change |
|------|--------|
| `packages/core/src/fs/recycle.rs` | **new** — platform-specific recycle bin |
| `packages/core/src/fs/audit.rs` | **new** — JSONL audit logger |
| `packages/core/src/fs/move_delete.rs` | **modify** — integrate recycle + audit |
| `packages/core/Cargo.toml` | **modify** — add objc2/windows deps |
| `packages/core/src/fs/tests/recycle_test.rs` | **new** |
| `packages/core/src/fs/tests/audit_test.rs` | **new** |

### Design

#### Recycle bin (platform-specific)
```rust
pub async fn recycle(path: &Path) -> Result<(), FsError>;

#[cfg(target_os = "macos")]
mod imp { /* NSWorkspace.recycle via objc2 */ }

#[cfg(target_os = "windows")]
mod imp { /* SHFileOperationW with FOF_ALLOWUNDO */ }

#[cfg(target_os = "linux")]
mod imp { /* ~/.local/share/Trash/files/ + .trashinfo */ }
```

#### Audit logger
```rust
pub struct AuditLog {
    path: PathBuf,  // ~/.local/share/localsend/audit.jsonl
}

impl AuditLog {
    pub fn new(config_dir: &Path) -> Result<Self, FsError>;
    pub fn record(&self, entry: AuditEntry) -> Result<(), FsError>;
    pub fn query(&self, since: DateTime, peer: Option<&str>) -> Result<Vec<AuditEntry>, FsError>;
    pub fn rotate_if_needed(&self) -> Result<(), FsError>;
}

pub struct AuditEntry {
    pub ts: i64,
    pub peer: String,
    pub op: String,  // "mkdir" | "upload" | "delete" | "move"
    pub path: String,
    pub result: String,  // "ok" | error code
    pub size: Option<u64>,
}
```

- JSONL format, one entry per line
- Daily rotation at midnight, retain 7 days
- Integrated into move_delete.rs: every write op records audit

### Acceptance Criteria
- [ ] 3-platform recycle bin implementation
- [ ] Audit log JSONL parseable by `jq`
- [ ] 7-day rotation automated
- [ ] Integrated with T-014 delete endpoint

---

## T-016: Client mutation UI

### Files to Create/Modify

| File | Change |
|------|--------|
| `app/lib/pages/remote_browser/widgets/context_menu.dart` | **new** — long-press menu |
| `app/lib/pages/remote_browser/widgets/multi_select_bar.dart` | **new** — bottom action bar |
| `app/lib/pages/remote_browser/widgets/rename_dialog.dart` | **new** |
| `app/lib/pages/remote_browser/widgets/move_target_picker.dart` | **new** — modal route |
| `app/lib/pages/remote_browser/widgets/delete_confirm_dialog.dart` | **new** |
| `app/lib/pages/remote_browser/widgets/properties_sheet.dart` | **new** |
| `app/lib/provider/network/fs/fs_mutation_provider.dart` | **new** — ReduxProvider |
| `app/lib/pages/remote_browser_page.dart` | **modify** — add gestures + state |
| `app/lib/router/app_router.dart` | **modify** — add move_target_picker route |
| `app/assets/i18n/strings_en.i18n.json` | **modify** — add keys |
| `app/assets/i18n/strings_zh.i18n.json` | **modify** — add keys |

### Design

#### State machine
```
Idle ──long press──> MultiSelect (selectedIds: {id})
                       │
                       ├──tap──> toggle select
                       │
                       └──close──> Idle

MultiSelect ──action──> { MoveDialog | DeleteDialog | Share | Properties }
```

#### Mutation provider
```dart
@ReduxProvider()
class FsMutationState {
  final Set<String> selectedIds;
  final bool isMultiSelect;
  final Map<String, FsEntryDto> snapshotBefore;  // for rollback
}
```

Actions:
- `FsEnterMultiSelect(firstId)`
- `FsToggleSelect(id)`
- `FsExitMultiSelect`
- `FsOptimisticDelete(path)` / `FsOptimisticMove(from, to)` / `FsOptimisticRename(path, newName)`
- `FsCommitMutation` / `FsRollbackMutation`

#### Move target picker
- Reuse `RemoteBrowserPage` subtree as modal route
- Top bar: "Move here" button
- Cross-mount not allowed (frontend validation + server backup)

### Acceptance Criteria
- [ ] Long press → menu; all actions (rename/move/delete/share/properties) work
- [ ] Multi-select mode with batch operations
- [ ] Delete confirmation dialog with recycle bin checkbox (default checked)
- [ ] Move target picker shows error on cross-mount
- [ ] Failure triggers state rollback (no "ghost" entries)

---

## T-017: Client optimistic updates + broadcast

### Files to Create/Modify

| File | Change |
|------|--------|
| `app/lib/provider/network/fs/fs_broadcast.dart` | **new** — in-memory event bus |
| `app/lib/pages/remote_browser/remote_browser_page.dart` | **modify** — pull-to-refresh + lifecycle |
| `app/lib/provider/network/fs/fs_list_provider.dart` | **modify** — add `refresh()` action |
| `app/lib/main.dart` | **modify** — init broadcast |

### Design

#### In-memory broadcast
```dart
class FsBroadcast {
  final _entriesController = StreamController<FsEvent>.broadcast();
  Stream<FsEvent> get onEvent => _entriesController.stream;

  void emit(FsEvent e) => _entriesController.add(e);
}

abstract class FsEvent {
  const FsEvent();
}
class FsEntriesChanged extends FsEvent { final String path; }
class FsRootsChanged extends FsEvent { final List<FsRoot> roots; }
class FsEntryRemoved extends FsEvent { final List<String> paths; }
```

#### Optimistic update flow
```dart
void _onMutation(FsMutation m) {
  final snapshot = state.entries;     // copy
  final newEntries = applyOptimistic(state.entries, m);
  dispatch(FsApplyOptimistic(newEntries));
  dispatch(FsBroadcastEmit(FsEntriesChanged(currentPath)));

  try {
    await isolate.dispatch(FsMutationAction(m));
  } catch (e) {
    dispatch(FsApplyOptimistic(snapshot));   // rollback
    dispatch(FsBroadcastEmit(FsEntriesChanged(currentPath)));
  }
}
```

#### Page lifecycle
```dart
@override
void initState() {
  super.initState();
  _sub = context.ref.read(fsBroadcastProvider).onEvent.listen((e) {
    if (e is FsEntriesChanged && e.path == currentPath) {
      dispatch(FsRefresh());
    } else if (e is FsRootsChanged) {
      dispatch(FsRootsUpdate(e.roots));
    }
  });
}

@override
void didChangeAppLifecycleState(AppLifecycleState s) {
  if (s == AppLifecycleState.resumed) {
    dispatch(FsRefresh());
  }
}
```

#### Pull-to-refresh
`RefreshIndicator` + `dispatch(FsRefresh())`

### Acceptance Criteria
- [ ] Local mutations reflect in UI within 100ms
- [ ] Failure rollback leaves no residual
- [ ] App resume triggers auto-refresh
- [ ] Pull-to-refresh works

---

## FRB Binding Updates

After T-014 Rust endpoints are done, expose them via FRB:

### `packages/localsend_isolates/rust/src/api/http.rs`
```rust
impl RsHttpClient {
    pub async fn fs_move(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        from: String,
        to: String,
        confirm: bool,
    ) -> Result<FsMoveResponse, RsHttpClientError>;

    pub async fn fs_delete(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        paths: Vec<String>,
        recycle: bool,
        confirm: bool,
    ) -> Result<FsDeleteResponse, RsHttpClientError>;

    pub async fn fs_stat(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: String,
    ) -> Result<FsStatResponse, RsHttpClientError>;
}
```

### `packages/localsend_isolates/rust/src/api/model.rs`
```rust
#[frb(mirror(FsMoveResponse))]
pub struct _FsMoveResponse {
    pub path: String,
}

#[frb(mirror(FsDeleteResponse))]
pub struct _FsDeleteResponse {
    pub deleted: Vec<String>,
    pub failed: Vec<FsDeleteFailure>,
}

#[frb(mirror(FsDeleteFailure))]
pub struct _FsDeleteFailure {
    pub path: String,
    pub reason: String,
}

#[frb(mirror(FsStatResponse))]
pub struct _FsStatResponse {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub mtime: i64,
    pub mime: Option<String>,
    pub supports_range: bool,
    pub etag: String,
}
```

Run `flutter_rust_bridge_codegen generate` from `packages/localsend_isolates/` after adding these.

---

## Testing Strategy

### Unit Tests (Rust)
- `cargo test -p localsend --features full` in `packages/core/`
- Cover all T-014 endpoints + T-015 audit/recycle
- Target ≥80% coverage for fs module

### Unit Tests (Dart)
- `fvm flutter test` in `app/`
- Cover fs_mutation_provider, fs_broadcast, optimistic update flow
- Target ≥70% coverage for new providers

### Integration Tests
- `app/test/integration/fs_crud_test.dart` — rename/move/delete flow
- Mock isolate responses for failure scenarios

### Manual Testing
- Long press → context menu appears
- Multi-select → bottom bar appears
- Delete → confirmation dialog → recycle bin checkbox
- Move → target picker → cross-mount error
- Optimistic update → immediate UI change → rollback on failure

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Cross-device move fails mid-way | Copy mode cleans up target on failure |
| Audit log grows unbounded | Daily rotation + 7-day retention |
| Optimistic update leaves ghost entries | Snapshot-based rollback on failure |
| Cross-mount move confusion | Frontend validates mount ID before request |
| macOS FFI complexity | Use `objc2` crate (safer than `objc`) |
| Windows recycle bin API deprecated | Use `SHFileOperation` for v1, migrate to `IFileOperation` later |

---

## Success Metrics

- All 4 tickets (T-014, T-015, T-016, T-017) accepted
- Unit test coverage ≥80% (Rust), ≥70% (Dart)
- No regression in P1/P2 functionality
- `fvm flutter analyze` passes with no new warnings
- `cargo clippy --features full` passes with no new warnings
- Manual testing on macOS + iOS passes all acceptance criteria

---

## Execution Plan

### Day 1-2: T-014 (Server endpoints)
- Implement move/delete/stat handlers in Rust
- Write unit tests
- Update FRB bindings
- Run codegen

### Day 3-4: T-015 (Audit + Recycle)
- Implement platform-specific recycle bin
- Implement audit logger
- Integrate with T-014
- Write unit tests

### Day 5-6: T-016 (Client UI)
- Create mutation provider
- Build context menu + multi-select widgets
- Build rename/move/delete dialogs
- Wire up gestures in remote_browser_page

### Day 7: T-017 (Optimistic updates)
- Implement broadcast bus
- Add optimistic update logic
- Add pull-to-refresh + lifecycle hooks
- Write integration tests

### Day 8: Testing + Polish
- Run full test suite
- Fix any regressions
- Update i18n keys
- Manual testing on devices
- Code review + PR preparation
