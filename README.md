# MacTap

Knock the MacBook. The app does the rest.

MacTap lives in the menu bar and turns taps on the chassis — or the desk underneath a still laptop — into shortcuts. One, two, or three knocks. Copy, paste, Accept, screenshots, media, or whatever you map.

Requires a MacBook with the built-in motion sensor (Apple Silicon). macOS 14.6 or later.

## Install

1. Download **[MacTap-2.1.0.dmg](https://github.com/jaskirat1616/mactap-app/releases/latest/download/MacTap-2.1.0.dmg)** from [Releases](https://github.com/jaskirat1616/mactap-app/releases).
2. Open the disk image and drag **MacTap** into Applications.
3. Open MacTap, then turn on **Accessibility** when asked so knocks can send shortcuts.

Detection itself does not need Accessibility. Actions do. If macOS asks to control System Events, allow that too.

## Use

- **Anywhere** — one, two, or three knocks on the chassis or desk.
- **Left & Right** — each edge is a different set of actions.
- **Presets** — Daily, Coding, Capture, Media, Focus.
- **Per app** — override knocks while a specific app is frontmost.

Open **Settings** from the menu extra to change layout, actions, and sensitivity.

Turn on **Accessibility** (and approve System Events if asked) so knocks can send shortcuts. Detection itself does not need those permissions. Actions do.

## Build from source

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MacTap.xcodeproj -scheme MacTap -configuration Debug \
  CONFIGURATION_BUILD_DIR=/Applications
open /Applications/MacTap.app
```

Set your own Apple Development Team in Xcode if you want a development-signed build. Local ad-hoc signing is enough to run it.

## Privacy

Taps are classified on-device. Nothing is uploaded. Gesture maps live in local defaults.

## License

MIT
