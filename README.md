# AirBeep

AirBeep is an iOS utility that silences the built-in call-recording disclosure tones. Flip one switch to replace the start and stop sounds with equal-length silence; flip it again to restore the original files from the automatic backup.

The original wallpaper browsing, importing, creation, and management features are not part of the AirBeep interface.

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
  - **iOS/iPadOS 26.0 – 26.6.1**
  - **iOS/iPadOS 27.0 – 27.2 B2**
- Xcode 27 or newer for local builds.
- The provided GitHub Actions workflow builds an unsigned IPA in the cloud.

> AirBeep relies on non-public system behavior. Compatibility can change between iOS releases. Removing a recording disclosure can affect whether another party is notified that a call is being recorded. Use the app only where permitted by local law and with the required consent.

## Build

Open `placard.xcodeproj`, select the `placard` target, set your signing team, and build to a physical device.

For an unsigned IPA, run the `Release unsigned IPA` workflow in GitHub Actions. The artifact is named `airbeep-v<version>-unsigned.ipa`.

## Credits

- [AirliftSilence](https://github.com/YiHoooong/AirliftSilence) for the silent tone assets and replacement research.
- [airlift](https://github.com/0xjohnnydev/airlift) by 0xjohnny for the AirTraffic and Airlock research retained in the project dependencies.
- [Placard](https://github.com/frs0n/placard) contributors for the original iOS project structure and container-access implementation.

## License

AirBeep is released under the [GNU General Public License v3.0](LICENSE).
