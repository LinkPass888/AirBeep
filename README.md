# AirBeep

> 🌍 **Languages:** English | [简体中文 (Simplified Chinese)](./README_zh-CN.md)

AirBeep is an iOS utility that silences the built-in call-recording disclosure tones. Flip one switch to replace the start and stop sounds with equal-length silence; flip it again to restore the original files from the automatic backup.


## Features

- One switch to silence the call-recording start and stop tones.
- Automatic backup of the original tone files before the first change — the backup is kept and never overwritten.
- File read-back verification after every write.
- One-tap restoration from the local backup.
- English and Simplified Chinese UI.

## How it works

AirBeep requests scoped container access for these system files:

- `/var/mobile/Library/CallServices/Greetings/default/StartDisclosureWithTone.m4a`
- `/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf`

The replacement files are based on the silent assets from AirliftSilence and keep the original durations. Backups are stored in the app's Documents directory under `AirBeepBackups`.

## Requirements

- A physical iPhone or iPad running one of the supported iOS/iPadOS releases:
  - **iOS/iPadOS 27.0 – 27.2 B2**
- Xcode 27 or newer for local builds.
- The provided GitHub Actions workflow builds an unsigned IPA in the cloud.

> AirBeep relies on non-public system behavior. Compatibility can change between iOS releases. Removing a recording disclosure can affect whether another party is notified that a call is being recorded. Use the app only where permitted by local law and with the required consent.

## Build

Open `airbeep.xcodeproj`, select the `airbeep` target, set your signing team, and build to a physical device.

For an unsigned IPA, run the `Release unsigned IPA` workflow in GitHub Actions. The artifact is named `airbeep-v<version>-unsigned.ipa`.

### Custom connection target

Set the `AIRLIFT_TARGET_HOST` build setting to LocalDevVPN's **Device IP** (default: `10.7.0.1`). The app configures the native library once at startup, so setup checks and tone operations use the same target without resetting it before each file operation.

First rebuild the patched native library with `scripts/build-airlift-xcframework.sh`, then build Release with `DEVELOPMENT_TEAM=<team> AIRLIFT_TARGET_HOST=<peer IP>`.

On iOS 26.4 and later, legacy Lockdown loopback connections also depend on the physical Wi-Fi subnet. Configure both LocalDevVPN addresses for the actual network, check for address conflicts, and use precise routes rather than changing an existing proxy configuration. Reconfigure after changing Wi-Fi subnets. Target selection alone does not guarantee system-file access or successful tone replacement.

## Credits

- [AirliftSilence](https://github.com/YiHoooong/AirliftSilence) for the silent tone assets and replacement research.
- [airlift](https://github.com/0xjohnnydev/airlift) by 0xjohnny for the AirTraffic and Airlock research retained in the project dependencies.
- [Placard](https://github.com/frs0n/placard) contributors for the original iOS project structure and container-access implementation.

## License

AirBeep is released under the [GNU General Public License v3.0](LICENSE).
