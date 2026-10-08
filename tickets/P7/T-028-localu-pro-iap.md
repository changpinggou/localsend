# T-028: LocalU Pro 一次性买断（IAP 解锁相册同步）

> Phase: P7 — Monetization
> Priority: P1
> Estimate: 3d（客户端 ~2d + 商店配置/沙盒验证 ~1d）
> Dependencies: T-027；外部依赖：App Store Connect / Google Play Console 开发者账号
> Spec: 方案 A —— 非消耗型 IAP「LocalU Pro」，一次性买断解锁相册同步
> Owner: Client

## 1. Background

T-027 的相册同步是 localU 最有商业价值的功能，选型结论为**方案 A：一次性买断**：

- 复用现有 `purchaseProvider` 管线（官方 `in_app_purchase` 插件 + Refena `ReduxProvider`），改动面最小
- 买断无续期/到期语义，**没有服务器也能自洽**（订阅方案 B 必须有后端判到期，排除）
- 现有 IAP 链路是一条**无验证的捐赠通道**：`_HandlePurchaseUpdate` 收到 `purchased/restored` 后直接 `completePurchase`，注释即 "No need to verify. It's just a donation..."。买断解锁沿用这一信任模型——不做票据校验，防君子不防小人（本地工具定位，可接受；见 §9）

现有资产（全部可复用）：

- `PurchaseItem` 枚举带 `androidId`/`iosId`，`platformProductId` 按平台取值
- `InitPurchaseStream` 已在启动时挂上 `purchaseStream`（`lib/config/init.dart:317`）
- `FetchPricesAndPurchasesAction` = 拉价格 + `restorePurchases()`（目前在**捐赠页进入时**才触发）
- 捐赠页（`donation_page.dart` + vm）提供完整的「拉价 → 购买 → 已购态 → 恢复」UI 范式
- FOSS 剥离机制：`# [FOSS_REMOVE_START/END]` 标记 + `remove_proprietary_dependencies.sh` 直接 `rm purchase_provider.dart` 并换 noop VM

## 2. Goal

- 新增非消耗型商品 **LocalU Pro**（Android/iOS 各一，SKU 见 §5.1）
- `isPro` 资格判定：运行时 `purchases` + 本地持久化缓存兜底（§5.2）
- T-027「同步相册」入口付费 gate（§5.4）
- Pro 解锁页（复用捐赠页管线，§5.5）
- FOSS / F-Droid 构建免费解锁；Windows / Linux / macOS 桌面端免费（§5.3）

## 3. Scope

### In scope
- `PurchaseItem.pro` 商品定义 + StoreKit 本地测试配置
- `purchaseProvider` 改造（缓存回写、启动静默恢复）
- `SettingsState.proCached` 持久化字段
- Pro gate provider（含 FOSS noop 替身）
- Pro 解锁页 + 设置页入口
- 远端浏览器同步按钮 gate
- i18n（en / zh-CN 先行，其余交 Weblate）
- 商店后台商品配置清单 + 审核注意事项（§8）

### Out of scope
- 服务器票据验证 / 收据防篡改对抗（方案 F，明确不做）
- 订阅 / 到期语义（方案 B，排除）
- 国内非 Play 安卓渠道支付（微信/支付宝聚合，方案 E）——Play Billing 在无 GMS 渠道不可用，渠道包需另立管线另行立项
- Windows / Linux / macOS 收费（桌面端全免费，见 §5.3）
- web send / 其他未来功能的商业化（gate 做成通用入口，但不预接）
- 促销码、家庭共享、价格 A/B

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/model/state/purchase_state.dart` | modify: `PurchaseItem` 加 `pro` |
| `app/lib/provider/purchase_provider.dart` | modify: `AddPurchaseAction` 命中 pro 时写缓存；新增启动静默恢复 action |
| `app/lib/config/init.dart` | modify: 启动时派发静默恢复（Android） |
| `app/lib/model/state/settings_state.dart` | modify: 加 `proCached` 字段 |
| `app/lib/provider/persistence_provider.dart` | modify: `isProCached()` / `setProCached()` |
| `app/lib/provider/settings_provider.dart` | modify: `setProCached()` 同步 state |
| `app/lib/provider/pro_gate_provider.dart` | new: `isProProvider` + FOSS noop 替身 |
| `app/lib/pages/pro/pro_page.dart` | new（克隆捐赠页结构） |
| `app/lib/pages/pro/pro_page_vm.dart` | new |
| `app/lib/pages/remote_browser_page.dart` | modify: `_onSyncPhotos` 入口 gate + 按钮锁角标 |
| `app/lib/pages/tabs/settings_tab.dart` | modify: 「LocalU Pro」入口（捐赠入口旁） |
| `ios/MyLocalSendStoreKit.storekit` | modify: 加 `localu_pro` 商品条目（本地沙盒测试用） |
| `app/assets/i18n/en.json`、`zh-CN.json` | new keys: `proPage.*`、`remoteBrowser.proLocked` |
| `support/scripts/remove_proprietary_dependencies.sh` | modify: gate 替换为 always-true |

## 5. Design

### 5.1 商品定义

```dart
enum PurchaseItem {
  // ……现有 donate5/10/20/50 不动……
  pro(androidId: 'localu_pro', iosId: 'localu_pro');
}
```

- SKU 两店同名 `localu_pro`（新商品无历史包袱，`platformProductId` getter 逻辑不变）
- 类型：**非消耗型**（`buyNonConsumable` 现有调用直接命中，`PurchaseAction` 无需改动）
- 商品元数据：显示名「LocalU Pro」/「同步相册 + 后续 Pro 功能」；本地化至少 en + zh-CN
- 定价建议区间：**¥12–¥18 / $1.99–$2.99** 一次性；Play Console 报名 Small Business Program（15% 分成），App Store Small Business Program 同理

### 5.2 资格判定与缓存

```
isPro = purchases.contains(PurchaseItem.pro)      // 运行时（本会话购买/恢复）
     || settings.proCached                         // 本地持久化兜底（重启/离线）
```

- 买断不过期，无服务器故**不做吊销**；`proCached` 只写不清（`PurchaseResetAction` 测试路径除外）
- **写入时机**：`AddPurchaseAction` 中命中 `PurchaseItem.pro` 时 → `settingsProvider.setProCached(true)`
- 首次升级发布时存量用户 `proCached == false` 但 `purchases` 空——没有兜底恢复前 gate 会误锁，由 §5.3 的 Android 静默恢复 + iOS 手动恢复覆盖。localU 尚未有付费用户，无迁移问题

### 5.3 启动恢复策略（关键决策）

`restorePurchases()` 在两个平台行为不同：

- **iOS**：触发系统登录框（`SKReceiptRefresh` / restoreCompletedTransactions）——**禁止在启动时静默调用**，弹窗打扰 + 审核风险
- **Android**：Google Play 静默返回历史购买——可以启动时调

因此：

| 场景 | 行为 |
|------|------|
| 启动 | Android：派发静默恢复（新 action，仅 Android，成功即回填缓存）；iOS：仅读缓存 + `purchaseStream` 补投 |
| Pro 页进入 | 沿用 `FetchPricesAndPurchasesAction`（拉价 + 恢复，两平台都触发，用户可感知） |
| Pro 页手动 | 「恢复购买」按钮（App Store 审核硬性要求入口存在） |

> 现有 `FetchPricesAndPurchasesAction` 有 `if (state.prices.isNotEmpty) return` 早退——价格只拉一次。Pro 页与捐赠页共用此 action 无冲突；若两页都会进入，第二次进入仍会走恢复（prices 非空时直接 return 了）——**恢复逻辑要挪出该早退分支**，改为「prices 空才拉价；恢复仅在 Pro 页手动触发 + Android 启动静默」，避免依赖隐式行为。

### 5.4 Gate 位置与形态

位置：`remote_browser_page.dart` 的 `_onSyncPhotos()` 入口（`IconButton onPressed` 之后、确认对话框之前）。

- **点击时 gate，不隐藏按钮**——保持可发现性，转化路径最短
- 按钮 tooltip 后缀锁提示（`t.remoteBrowser.proLocked`）；图标可加小角标（`Icons.lock`，右下 12px）
- Gate 流程：`isPro == false` → `push(ProPage)`（带来源埋点字段可后补）；`isPro == true` → 原确认对话框流程不变
- 判定走 `pro_gate_provider`，UI 不直接读 `purchaseProvider`——为 FOSS 替换留唯一缝合点：

```dart
// 正常构建
final isProProvider = Provider((ref) {
  final purchase = ref.watch(purchaseProvider);
  final settings = ref.watch(settingsProvider);
  return purchase.state.purchases.contains(PurchaseItem.pro) || settings.state.proCached;
});

// FOSS 构建（脚本整体替换 pro_gate_provider.dart）
final isProProvider = Provider((ref) => true);
```

### 5.5 Pro 解锁页

克隆捐赠页管线（`donation_page.dart` / `donation_page_vm.dart` → `pro_page.dart` / `pro_page_vm.dart`）：

- 单卡片：商品名 + 一句话价值（相册同步）+ 价格按钮（`vm.prices[PurchaseItem.pro] ?? '...'`，拉价失败禁用）
- 已购态：✓ + 「感谢支持」，按钮禁用（同捐赠页 `vm.purchased.isNotEmpty` 分支）
- 「恢复购买」TextButton（走 `PurchaseRestoreAction`）
- pending → 全屏进度遮罩（同捐赠页）
- 不放 GitHub Sponsors / Ko-fi 等外链——**解锁 UI 出现外部支付引导是审核拒绝项**；捐赠页保持独立不受影响
- 设置页入口：`settings_tab.dart` 捐赠入口旁加「LocalU Pro」，已购时显示已解锁徽标

### 5.6 启动接线

`init.dart` 在 `InitPurchaseStream()` 之后：

```dart
if (defaultTargetPlatform == TargetPlatform.android) {
  ref.redux(purchaseProvider).dispatchAsync(SilentRestoreAction());  // 静默恢复 + 回填缓存
}
```

iOS 不派发（§5.3）。`SilentRestoreAction` = `restorePurchases()` try/catch 吞错（同 `PurchaseRestoreAction`，离线/未装商店静默失败）。

### 5.7 i18n

```
proPage: { title, subtitle, buy, purchased, restore, priceUnavailable, thanks }
remoteBrowser: { proLocked }   // "相册同步为 LocalU Pro 功能"
```

en / zh-CN 先行写死，其余 locale 走 Weblate 流程（与 T-027 相同）；`app/test/unit/i18n_test.dart` 校验 locale 集合。

### 5.8 FOSS / F-Droid

`remove_proprietary_dependencies.sh` 增量：

```sh
# pro_gate_provider.dart 整体替换为 always-true（与 donation noop 同策略）
sed -i 's/…正常实现…/final isProProvider = Provider((ref) => true);/' lib/provider/pro_gate_provider.dart
# 或直接 cat > 覆写该文件（脚本内已 cd app，写单文件更稳）
```

- `pro_gate_provider.dart` 顶部注释注明「FOSS 构建会被脚本覆写为 always-true」
- `pro_page.dart` / `pro_page_vm.dart` 无需进 FOSS 剥离名单：gate 恒真后 Pro 页不可达；`purchase_provider.dart` 仍被 `rm`，Pro 页 import 会被 FOSS 构建的 analyze 抓出——**因此 Pro 页/VM 也要进 `# [FOSS_REMOVE_START/END]` 包裹或脚本删除名单**（实施时二选一，推荐同捐赠页的 START/END 包裹法）

### 5.9 桌面端策略

`checkPlatformSupportPayment()` 现含 macOS（`platform_check.dart:59`）。产品决策：

- **gate 仅在 Android + iOS 生效**（新 `checkProGatePlatform()`，列 android/iOS）
- Windows / Linux / macOS（含未来 MAS 版）**全免费**——桌面是 LocalSend 的传统强项与口碑来源，且非商店分发无法收费
- 未来若 MAS 付费上架再收紧 `checkProGatePlatform()`，一处改动

## 6. UI / Interaction

### 同步按钮 gate

```
┌─────────────────────────────────────┐      ┌─────────────────────────┐
│ ← 工作盘 (D:) / Photos  [🔄][🔒≡]  │      │      LocalU Pro          │
│                                     │      │                          │
│  未购：点击「同步相册」→ Pro 页      │ ───▶ │  ✓ 相册增量同步           │
│  已购：点击 → 原确认对话框           │      │  （后续 Pro 功能列出）    │
│                                     │      │                          │
└─────────────────────────────────────┘      │  ┌────────────────────┐  │
                                             │  │  ¥18.00  解锁       │  │
                                             │  └────────────────────┘  │
                                             │       恢复购买            │
                                             └─────────────────────────┘
```

- 价格文案来自商店（本地货币），拉价失败显示 `...` 并禁用按钮（同捐赠页）
- 购买成功：系统支付 sheet → `purchaseStream` 回调 → 卡片转已购态 → 用户返回 → 同步按钮直接可用（gate 读 provider，无需手动刷新）

## 7. Test plan

### 单元
- `isPro` 判定矩阵：purchases 有 pro / 仅 proCached / 两者皆无 / 仅捐赠项（不算 pro）
- `AddPurchaseAction` 命中 pro → `setProCached(true)`；命中 donate 系列不写缓存
- `PurchaseResetAction` 清运行态；缓存清除仅测试路径
- `checkProGatePlatform()`：android/iOS true，windows/linux/macos false
- FOSS 替身：`isProProvider` 恒真

### 集成（本地 StoreKit + Play 内部测试轨道）
- `ios/MyLocalSendStoreKit.storekit` 加 `localu_pro` 条目后，Xcode 本地沙盒走完：购买 → 解锁 → 杀进程重启仍解锁（缓存）→ 删 app 重装 → 恢复购买 → 解锁
- Android：Play 内部轨道，购买 → 重启仍解锁（启动静默恢复）→ 断网启动读缓存

### 手动
1. 未购状态点「同步相册」→ 进 Pro 页，同步不执行
2. 购买成功返回 → 再点同步 → 确认对话框正常
3. Pro 页「恢复购买」在已购/未购两态下行为正确
4. 设置页 Pro 入口显示已解锁徽标
5. Windows / Linux 构建：同步按钮无 gate
6. FOSS 脚本跑完后：同步无 gate、`flutter analyze` 通过（Pro 页被剥离后无悬空 import）

## 8. Acceptance criteria

- [ ] `PurchaseItem.pro` 两店同名 SKU，非消耗型，价格按钮显示本地货币
- [ ] 未购点击同步 → Pro 页；已购点击同步 → 原流程
- [ ] 购买后无需重启即可使用相册同步；重启/离线后仍解锁（缓存）
- [ ] iOS 重装后可经 Pro 页「恢复购买」解锁；Android 启动静默恢复不弹任何系统框
- [ ] 桌面端（Win/Linux/macOS）无 gate；F-Droid FOSS 构建无 gate 且不含 `in_app_purchase` 依赖
- [ ] 捐赠页行为不变；捐赠项不触发 Pro 解锁
- [ ] 解锁 UI 无任何外部支付引导（审核合规）
- [ ] `fvm dart format` / `flutter analyze` / `flutter test` 全绿；FOSS 脚本跑完 analyze 仍绿

## 9. Risks / Notes

- **无验证的信任模型**：越狱/篡改可绕过 gate。接受（与现有捐赠通道同一信任级别）；未来上服务器校验是独立工单，gate 收敛在 provider 层，届时只改 `isProProvider`
- **iOS 缓存丢失**：重装/换机后 `proCached` 归零，需手动恢复（无服务器下的标准做法）；恢复入口不存在才是审核问题，入口必须有
- **价格不可本地计算**：价格来自商店本地货币，UI 只显示 `queryProductDetails` 结果；商店未配置/未过审时按钮禁用
- **国内安卓渠道**：无 GMS 设备上 `queryProductDetails` 直接失败——表现为价格拉不到、按钮禁用，属可接受降级；真正的渠道支付（微信/支付宝）另立项
- **审核注意**：解锁功能必须真实可用（T-027 已上线）；IAP 商品截图/描述与实际一致；不得引导外部支付；隐私清单不含追踪
- **`FetchPricesAndPurchasesAction` 早退分支**（§5.3 引注）：改造时把「恢复」从「拉价」的早退中解耦，否则 Pro 页第二次进入不会恢复——实施时补单测锁定
