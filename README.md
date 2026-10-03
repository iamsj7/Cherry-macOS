# CherryTools

CherryTools is a native Apple Silicon macOS menu bar utility for inspecting ports, keeping clipboard history, and cutting files in Finder. It requires macOS 14 or later and has no Dock icon.

## Features

- **Ports:** See listening TCP ports and optionally UDP sockets. Search by port, process, project, user, or PID; filter by runtime; inspect process details; and terminate a process after confirmation. The normal view hides system processes, while **Show all** includes those visible to your account. CPU, memory, and energy values come from macOS process counters. Energy may be unavailable until a second sample.
- **Clipboard:** Keep copied text, files, and images locally for up to 30 days. Press **Control–Option–V** to open history, then select an item to copy it again.
- **Finder cut:** Press **Command–X** in Finder to mark selected files for moving, then **Command–V** in Finder to move them. This requires Accessibility permission. CherryTools plays macOS's built-in Tink sound when cutting; you can turn it off in Settings.
- **Settings:** Configure launch at login, menu bar icon visibility, the menu bar port count, clipboard history, and Finder cut. **Control–Option–Command–M** restores a hidden menu bar icon.

## Build and run

Install Xcode and its command line tools on an Apple Silicon Mac, then run:

```sh
./scripts/build-app.sh
open dist/CherryTools.app
```

The script builds an arm64 app bundle and signs it locally. Quit any running CherryTools copy before opening a new build. The bundle identifier is `com.shaikjaleel.cherrytools`.

To use Finder cut, open **CherryTools → Settings → Shortcuts**, grant Accessibility access in System Settings, then return to CherryTools. If the shortcut is not active, click **Enable Accessibility access** in Settings once more.

## Data and permissions

Clipboard history stays on this Mac in `~/Library/Application Support/CherryTools/Clipboard`. CherryTools polls for clipboard changes every 1.5 seconds. It scans ports every eight seconds while the Ports panel is open; the optional menu bar count refreshes every 30 seconds. macOS may restrict information about other users' or protected processes, and may refuse to terminate them. CherryTools does not request administrator privileges.

The locally signed bundle is for development and personal installation. Distributing a downloadable app to other Macs requires Developer ID signing and notarization.

## License

CherryTools is released under [the Unlicense](UNLICENSE). Anyone may use, modify, redistribute, or sell it without attribution requirements. Made by Shaik Jaleel in Muscat.
