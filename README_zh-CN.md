# AirBeep

> 🌍 **Languages:** [English](./README.md) | 简体中文

AirBeep 是一款 iOS 工具，用于静音系统内置的通话录音提示音。只需拨动一个开关，即可将开始与结束提示音替换为等长静音；再次拨动开关，即可从自动备份中恢复原始文件。


## 功能特性

- 一个开关即可静音通话录音的开始与结束提示音。
- 首次修改前自动备份原始提示音文件 —— 备份会被保留且绝不会被覆盖。
- 每次写入后都会进行文件回读校验。
- 一键从本地备份恢复。
- 支持英文与简体中文界面。

## 工作原理

AirBeep 会请求以下系统文件的容器级访问权限：

- `/var/mobile/Library/CallServices/Greetings/default/StartDisclosureWithTone.m4a`
- `/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf`

替换文件基于 AirliftSilence 的静音资源，并保持原始时长。备份保存在应用 Documents 目录下的 `AirBeepBackups` 中。

## 系统要求

- 一台受支持的 iOS/iPadOS 系统的实体 iPhone 或 iPad：
  - **iOS/iPadOS 27.0 – 27.2 B2**
- 本地构建需 Xcode 27 或更高版本。
- 仓库提供的 GitHub Actions 工作流可在云端构建 unsigned IPA。

> AirBeep 依赖非公开的系统行为，不同 iOS 版本之间兼容性可能发生变化。移除录音提示音可能影响对方是否收到“通话正在被录音”的通知。请在当地法律允许并取得必要同意的情况下使用本应用。

## 构建

打开 `airbeep.xcodeproj`，选择 `airbeep` target，设置你的签名团队，然后构建到实体设备。

如需构建 unsigned IPA，请在 GitHub Actions 中运行 `Release unsigned IPA` 工作流。成品文件名为 `airbeep-v<version>-unsigned.ipa`。

## 致谢 / Credits

- 感谢 [AirliftSilence](https://github.com/YiHoooong/AirliftSilence) 提供的静音音频资源与替换方案研究。
- 感谢 [airlift](https://github.com/0xjohnnydev/airlift)（作者 0xjohnny）提供的 AirTraffic 与 Airlock 研究，其作为项目依赖被保留。
- 感谢 [Placard](https://github.com/frs0n/placard) 的贡献者提供的原始 iOS 项目结构与容器访问实现。

## 许可证 / License

AirBeep 以 [GNU 通用公共许可证 v3.0](LICENSE) 发布。