# Changelog

All notable changes to **AirBeep** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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