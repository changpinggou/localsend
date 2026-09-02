# T-024: Server 路径穿越 fuzz 测试

> Phase: P6 — Hardening
> Priority: P0
> Estimate: 2d
> Dependencies: T-004
> Spec: REQUIREMENTS.md §4.1 N-SEC-1、§7 AC-3
> Owner: Server + 安全

## 1. Background

T-004 实现了 PathGuard，但要保证它在面对恶意输入时无懈可击。手工测试覆盖不足；用 `cargo-fuzz` 自动生成随机路径。

## 2. Goal

- 建立 `fuzz_path_guard` fuzz target
- 集成到 CI（nightly）
- 至少 30 min fuzz 跑出 0 crash / 0 unauthorized success
- 增加 OWASP Path Traversal 用例集

## 3. Scope

### In scope
- `cargo-fuzz` 集成
- 3 个 fuzz target（`check_input` / `normalize_input` / `combined_with_fs`）
- OWASP 用例集
- CI 集成（nightly workflow）

### Out of scope
- 性能 fuzz（不卡 CPU 即可）
- 端到端 fuzz（已由 T-003 集成测试覆盖）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/fuzz/Cargo.toml` | new |
| `packages/core/fuzz/fuzz_targets/path_guard.rs` | new |
| `packages/core/fuzz/fuzz_targets/normalize.rs` | new |
| `packages/core/fuzz/fuzz_targets/combined.rs` | new |
| `.github/workflows/fuzz.yml` | new（nightly 30 min） |
| `packages/core/src/fs/tests/owasp_path_traversal.rs` | new |

## 5. Design

### 5.1 Fuzz target

```rust
// packages/core/fuzz/fuzz_targets/path_guard.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
use localsend::fs::{FsPath, PathGuard, MountTable};

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        let table = MountTable::from_config(vec![]);
        let guard = PathGuard::new(&table);
        let _ = guard.check(s);   // 不 panic 即可
    }
});
```

### 5.2 OWASP 用例集

参考 <https://owasp.org/www-community/attacks/Path_Traversal>：

```rust
#[test]
fn owasp_dotdot_attack() {
    let cases = vec![
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32",
        "....//....//....//etc",
        ".%2e/.%2e/.%2e/etc",
        "..%252f..%252f..%252fetc",
        "..%c0%af..%c0%afetc",
        "..%ef%bc%8fetc",
        "/etc/passwd",
        "\\?\\D:\\..\\etc",
    ];
    for c in cases {
        let r = guard.check(c);
        assert!(matches!(r, Err(FsError::PathDenied(_))), "leaked: {c}");
    }
}
```

### 5.3 CI

```yaml
# .github/workflows/fuzz.yml
name: Fuzz
on:
  schedule: [{ cron: '0 3 * * *' }]   # 每日 03:00 UTC
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: cargo install cargo-fuzz
      - run: cd packages/core && cargo fuzz run path_guard -- -max_total_time=1800
```

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元

- OWASP 30+ 用例覆盖
- Fuzz 24 h 不爆 0 crash

### CI

- 每日 30 min fuzz 通过

## 8. Acceptance criteria

- [ ] 3 个 fuzz target 在 nightly 跑通
- [ ] 30+ OWASP 用例全过
- [ ] fuzz 1 h 无 panic
- [ ] 不通过 fuzz 阻断发布

## 9. Risks / Notes

- cargo-fuzz 需要 nightly 工具链
- 移动端 CI（iOS/Android）不跑 fuzz；只 Linux runner
- 如果 fuzz 找到 bug：修补后必须 30 min 内重跑确认
