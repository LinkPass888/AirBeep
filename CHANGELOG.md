# Changelog

All notable changes to **AirBeep** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.5.2] - 2026-10-19

### English / Added
- **Check tone status button.** The current tone state can now be checked on
  demand from the home screen. The read channel is unreliable on some iOS
  releases (the AirTraffic move step never completes there), so the check
  reports one of three outcomes: silenced, originals still in place, or
  unverifiable on this device. It never runs automatically and never gates an
  operation.

### English / Changed
- After silencing, the success alert no longer claims a verified result when
  the read-back could not confirm it; it says the silence was written but
  unverified and points at the tone status check. This covers the
  [issue #6](https://github.com/LinkPass888/AirBeep/issues/6) report where the
  write channel returns success on iOS 27.x while the tones never change.

---

### 中文 / 新增
- **校验提示音状态按钮。** 可在首页按需检测当前提示音状态。部分 iOS 版本上
  读取通道不可靠（AirTraffic 搬运步骤始终无法完成），因此检测结果分为三种：
  已静音、原始提示音仍在、本机无法校验。该检测绝不自动运行，也不会阻断
  任何操作。

### 中文 / 变更
- 静音后的成功弹窗在回读校验无法确认时不再直接宣称成功，改为提示"静音
  已写入、结果未经校验"，并引导使用提示音状态校验。对应
  [issue #6](https://github.com/LinkPass888/AirBeep/issues/6) 反馈的
  iOS 27.x 上写入通道返回成功但提示音实际未变的问题。

---

## [2.5.1] - 2026-10-18

### English / Changed
- **iOS 18 is now supported.** The deployment target drops from iOS 27 to
  iOS 18.0; the supported range is **iOS/iPadOS 18.0 – 27.2 B2**, and later
  versions cannot be supported. Below iOS 27 the system does not support
  on-device pairing — generate a pairing file on a computer with
  [iloader](https://github.com/nab138/iloader) or
  [idevice_pair](https://github.com/jkcoxson/idevice_pair) and import it.
- **The switch is gone.** The home screen now shows two independent actions:
  **Silence recording tone**, and either **Back Up Original Tones** (shown
  until a complete backup exists) or **Restore original tone**. The current
  tone state is no longer displayed — detecting it needs a device read that
  is unreliable on some iOS releases. Successful operations confirm with an
  alert instead.
- The home page version line shows the running system version beside the app
  version, e.g. `iOS 27.1  AirBeep v2.5.1 (9)` (`iPadOS` on iPad).
- Backup is a standalone action: back the originals up before silencing so
  they are always recoverable; the button then flips to Restore. The
  automatic-backup note sits under that button.

### English / Fixed
- **Flaky airlift reads no longer abort the whole operation.** Each tone file
  is read independently; a failed read is skipped and logged instead of
  failing the silence/restore. The write channel's return code is the source
  of truth, and read-back verification degrades to a log entry when a re-read
  is unavailable.
- **Loopback connect no longer falsely demands Wi-Fi.** Wi-Fi presence is now
  read from the live interface table (`getifaddrs`) instead of
  `NWPathMonitor`, which reports unsatisfied once the VPN owns the default
  path. Wi-Fi is still required.
- The third writable tone file `StartDisclosure.caf` is now replaced too
  (skipped automatically on releases that do not ship it).
- Restore without a backup explains the language-change recovery path instead
  of failing with a generic "no backup" error.
- Removed the non-public-behavior disclaimer from the bottom of the home page.

### English / Added
- **Advanced settings** (About page): set a custom device IP for the loopback
  connection, and inspect the live network-interface table with tunnel/Wi-Fi
  state — self-diagnosis for the "connection refused / wrong subnet" reports.
- Runtime interface scan: tunnel dials now adapt to the actual network via
  `al_set_target_hosts` without any route probing.
- Localization hardened: two validation scripts keep the EN/zh-Hans catalogs
  in sync (identical keys, matching placeholders, no untranslated UI literals).

---

### 中文 / 变更
- **支持 iOS 18。** 最低系统要求由 iOS 27 降至 iOS 18.0，支持范围为
  **iOS/iPadOS 18.0 – 27.2 B2**，之后的版本无法支持。iOS 27 以下的系统
  不支持本机配对，请在电脑上用 [iloader](https://github.com/nab138/iloader) 或
  [idevice_pair](https://github.com/jkcoxson/idevice_pair) 生成配对文件后导入。
- **取消开关设计。** 首页改为两个独立操作：**静音录音提示音**，以及
  **备份原始提示音**（尚无完整备份时显示）或 **恢复原始提示音**。不再显示
  当前提示音状态——检测状态需要在部分 iOS 版本上不可靠的设备读取；操作
  成功后以弹窗提示。
- 首页版本行在软件版本号左侧显示当前系统版本，例如
  `iOS 27.1  AirBeep v2.5.1 (9)`（iPad 上显示 `iPadOS`）。
- 备份成为独立操作：可先备份再静音，原音始终可找回；按钮随后切换为恢复，
  自动备份说明位于该按钮下方。

### 中文 / 修复
- **airlift 读取偶发失败不再导致整个操作中断。** 每个提示音文件独立读取，
  失败仅跳过并记录日志；以写入通道的返回码为准，回读校验在无法读取时
  降级为日志记录。
- **回环连接不再误报"需要连接 Wi-Fi"。** Wi-Fi 状态改由实时接口表
  （`getifaddrs`）判断，不再使用在 VPN 接管默认路由后总报告不可用的
  `NWPathMonitor`。Wi-Fi 仍为必需条件。
- 同时替换第三个可写提示音文件 `StartDisclosure.caf`（未提供该文件的
  系统版本自动跳过）。
- 无备份时的恢复会明确指引"更改系统语言"恢复路径，不再报模糊的
  "无备份"错误。
- 删除首页底部"依赖非公开系统行为"的免责提示。

### 中文 / 新增
- **高级设置**（关于页）：可为回环连接设置自定义设备 IP，并查看带
  隧道/Wi-Fi 状态的实时网络接口列表，自行排查"连接被拒绝 / 网段不对"问题。
- 运行时接口扫描：通过 `al_set_target_hosts` 让隧道拨号适配实际网络，
  不做任何路由探测。
- 本地化加固：新增两个校验脚本保证中英文目录一致（键相同、占位符匹配、
  无未翻译界面文案）。

---

**Full Changelog**: [v2.4.1...v2.5.1](https://github.com/LinkPass888/AirBeep/compare/v2.4.1...v2.5.1)

## [2.4.1] - 2026-10-17

### English / Fixed
- Configure the native Airlift target once from `AIRLIFT_TARGET_HOST` so setup checks and tone operations share the configured LocalDevVPN peer.
- Complete the Lockdown heartbeat handshake before accessing network services. Keep the existing heartbeat client alive for each operation and abort its task when the tunnel is dropped, including cached-route connections.
- Rebuild the pinned native dependency with the file-read and heartbeat patch; retain checksum and exported-symbol verification.

### 中文 / 修复
- 支持通过构建设置配置 Airlift 连接地址，连接检查与提示音读写共用同一目标。
- 修复网络 Lockdown 路径缺少 heartbeat 导致服务连接被系统关闭的问题；保活仅限本次操作生命周期。

## [2.4.0] - 2026-10-10

> **English** — Release notes. | **中文** — 发行说明见下方中文版。

### English / Changed
- Removed the automatic tone-state check that ran at app launch. Some users saw
  a startup check get stuck and the switch stay disabled because the underlying
  airlift read could not finish on their iOS release. The app now restores the
  last known state from cache and performs no file access until the user flips
  the switch.
- If anything goes wrong with the tones, you can force the original system
  tones back by changing the system language on the device.

---

### 中文 / 变更
- 移除 app 启动时自动执行的提示音文件状态校验。此前部分用户会因启动校验
  卡住、开关一直处于灰色不可用状态——其根本原因是底层 airlift 读取在部分
  iOS 版本上无法完成。现在打开 app 不再做任何文件读取，改为从本地缓存恢复
  上次的状态，仅在用户拨动开关时才进行实际操作。
- 若提示音出现异常，可通过**更改系统语言**强制恢复为系统默认提示音。

---

**Full Changelog**: [v2.3.0...v2.4.0](https://github.com/LinkPass888/AirBeep/compare/v2.3.0...v2.4.0)

## [2.3.0] - 2026-10-09

> **English** — Release notes. | **中文** — 发行说明见下方中文版。

### English / Fixed
- **Xcode 27 build failure.** With `-default-isolation=MainActor`, `@escaping`
  closures can no longer implicitly reference `self`. The silence and restore
  operations now capture `self` explicitly, so the unsigned IPA builds again.
- **iOS 27.0.1 "AirTraffic did not recover"** on read: the airlift read probe
  now targets a non-empty payload and emits more diagnostic logging.

### English / Added
- Runtime log collection (`AirBeepLog`) with on-device export in the About page
  for easier troubleshooting.
- Manual pairing-file import via `UIDocumentPickerViewController` (`asCopy`),
  avoiding the sandbox security-scope read failure.
- Screen keeps awake and shows a prominent "do not exit the app" warning banner
  while a silence / restore operation is running.

### English / Security
- Removed the unused `BadQuery` vulnerability; only `airlift` is retained.

### English / Infrastructure
- Renamed the product from `placard` to `airbeep` across the project, scheme,
  bridging header, workflow, and scripts.
- Updated supported range to iOS/iPadOS 18.0 – 27.2 B2 (aligned with AirCard /
  AirliftSilence).

---

### 中文 / 已修复
- **修复 Xcode 27 构建失败**：由于 `-default-isolation=MainActor`，`@escaping`
  闭包不能再隐式引用 `self`。静音与恢复操作改为显式捕获 `self`，unsigned
  IPA 重新可以构建。
- **修复 iOS 27.0.1 "AirTraffic did not recover"**（读取时）：airlift 读取
  探针改为非空 payload，并增加诊断日志。

### 中文 / 新增
- **运行时日志采集**（`AirBeepLog`）+ 关于页一键导出，便于排查问题。
- **手动导入配对文件**：改用 `UIDocumentPickerViewController`（`asCopy`），
  规避沙盒安全作用域读取失败。
- **操作中屏幕常亮**，并显示醒目的"操作中请不要退出软件"提示横幅。

### 中文 / 安全
- 移除未使用的 `BadQuery` 漏洞，仅保留 `airlift`。

### 中文 / 基础设施
- 产品由 `placard` 更名为 `airbeep`（项目、scheme、bridging header、
  workflow、脚本全部同步）。
- 支持范围更新为 **iOS/iPadOS 18.0 – 27.2 B2**（与 AirCard / AirliftSilence
  对齐）。

---

**Full Changelog**: [v2.2.0...v2.3.0](https://github.com/LinkPass888/AirBeep/compare/v2.2.0...v2.3.0)