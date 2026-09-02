# T-018: Server 热插拔监听（macOS / Windows / Linux）

> Phase: P4 — Hotplug
> Priority: P0
> Estimate: 3d
> Dependencies: T-002
> Spec: REQUIREMENTS.md §3.2.1 F-S-3、§7 AC-4
> Owner: Server + 平台

## 1. Background

挂载端要监听 USB / 磁盘热插拔事件，更新 `MountTable`，并通知所有已配对移动端刷新。不同平台机制差异大。

## 2. Goal

跨平台热插拔事件源，统一暴露为：

```rust
pub struct MountWatcher { ... }
impl MountWatcher {
    pub fn watch(mount_table: Arc<RwLock<MountTable>>, config: HotplugConfig) -> Result<Self>;
    pub fn events(&self) -> broadcast::Receiver<MountEvent>;
}
pub enum MountEvent { Added(FsRoot), Removed(String) }
```

## 3. Scope

### In scope
- macOS：CoreServices `DARegisterCallback` 或 `NSWorkspace` notification（通过 FFI）
- Windows：`WM_DEVICECHANGE` 消息（走 FFI 子线程）
- Linux：`udev` + `inotify` 监听 `/dev/disk/by-uuid/` + `/media/$USER/`
- 与 `MountTable` 联动：add/remove 后立即更新
- 与 T-019 推送通道联动：发出 `FsRootsChanged` 事件

### Out of scope
- iOS / Android 端（mobile 不需要监听自己盘符变化）
- 移动盘 / 系统盘 / 网络盘类型细分（统一作为可挂载设备）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/hotplug/mod.rs` | new |
| `packages/core/src/fs/hotplug/macos.rs` | new |
| `packages/core/src/fs/hotplug/windows.rs` | new |
| `packages/core/src/fs/hotplug/linux.rs` | new |
| `packages/core/src/fs/mount.rs` | extend：MountTable update API |
| `packages/core/Cargo.toml` | 加 udev（linux）/ cocoa（macOS）/ windows crate |
| `packages/core/src/fs/tests/hotplug_test.rs` | new（mock 事件注入） |

## 5. Design

### 5.1 公共抽象

```rust
// packages/core/src/fs/hotplug/mod.rs
pub struct MountWatcher {
    inner: platform::Watcher,
    event_tx: broadcast::Sender<MountEvent>,
}

pub struct HotplugConfig {
    pub poll_interval: Duration,      // fallback：5 s
}

impl MountWatcher {
    pub async fn run(&self, mount_table: Arc<RwLock<MountTable>>) {
        let mut events = self.inner.subscribe();
        while let Some(ev) = events.next().await {
            let mut table = mount_table.write().await;
            match &ev {
                MountEvent::Added(root) => {
                    let snapshot = enumerate_mounts().await;  // 重新拉一遍
                    *table = MountTable::from_config(snapshot);
                }
                MountEvent::Removed(id) => {
                    table.remove(id);
                }
            }
            drop(table);
            let _ = self.event_tx.send(ev);
        }
    }
}
```

### 5.2 macOS

```rust
// hotplug/macos.rs
use objc2::{msg_send, runtime::AnyObject};

pub struct Watcher { tx: broadcast::Sender<MountEvent> }

impl Watcher {
    pub fn subscribe(&self) -> broadcast::Receiver<MountEvent> { ... }
    pub fn start(&self) -> Result<()> {
        // 注册 NSWorkspace didMountNotification / didUnmountNotification
        // 在主 RunLoop 调 DARegisterCallback
    }
}
```

走 cocoa / objc2 crate。

### 5.3 Windows

```rust
// hotplug/windows.rs
pub fn start(tx: broadcast::Sender<MountEvent>) -> Result<()> {
    // 起一个 std::thread
    // 注册窗口类接收 WM_DEVICECHANGE / DBT_DEVICEARRIVAL / DBT_DEVICEREMOVECOMPLETE
    // 用 GetLogicalDrives 前后对比
}
```

### 5.4 Linux

```rust
// hotplug/linux.rs
pub async fn start(tx: broadcast::Sender<MountEvent>) -> Result<()> {
    use udev::{EventType, MonitorBuilder};

    let monitor = MonitorBuilder::new()?
        .match_subsystem("block")?
        .listen()?;

    while let Some(event) = monitor.iter().next() {
        match event.event_type() {
            EventType::Add => tx.send(MountEvent::Added(...)),
            EventType::Remove => tx.send(MountEvent::Removed(...)),
            _ => {}
        }
    }
}
```

## 6. UI / Interaction

不在本工单。挂载端设置页有"已挂载设备"列表（v1 沿用 T-002 的列表展示，加 watch 触发刷新）。

## 7. Test plan

### 单元

- `mount_watcher_emits_added_on_event`
- `mount_watcher_emits_removed_on_event`
- `mount_table_updates_on_watcher_event`
- `mount_watcher_fallback_polling`（注入 MockWatcher，5 s 轮询）

### 集成

- macOS CI：mock FFI 事件
- Windows CI：mock WM_DEVICECHANGE
- Linux CI：使用 udev mock crate

## 8. Acceptance criteria

- [ ] 3 平台 Watcher 实现 + 单测
- [ ] MountTable 自动更新
- [ ] 触发事件时同时发 `FsRootsChanged`（与 T-019 通道集成）
- [ ] 测试覆盖 3 s 内 MountTable 反映新挂载（AC-4）

## 9. Risks / Notes

- macOS `DARegisterCallback` API 已 deprecated 但仍可用；新代码应用 `NSWorkspace` notification
- Windows GUI 程序必须先有 message loop；CLI / 单元测试用 fallback polling
- Linux udev 监听需要 udev 守护进程；容器内需要 mock
- 频繁插拔（< 1 s）要做去抖（debounce 500 ms）
