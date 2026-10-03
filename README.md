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

## GitHub Releases

Add a versioned entry at the top of [CHANGELOG.md](CHANGELOG.md) and push it to `main`:

```md
## [0.1.0] - 2026-10-03

- Initial public release.
```

The [release workflow](.github/workflows/release.yml) runs on an Apple Silicon GitHub runner whenever `CHANGELOG.md` changes. It reads the newest version, skips versions that already have a Git tag, builds an arm64 app, signs it with your Developer ID, notarizes and staples it, then publishes a ZIP and SHA-256 checksum as a GitHub Release. The changelog entry becomes the release notes. The app version inside the ZIP comes from the heading. You can rerun the workflow manually from the Actions tab after fixing a failed run.

Before the first release, add these repository Actions secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 text of an exported **Developer ID Application** `.p12` certificate and private key. On macOS: `base64 < certificate.p12 | tr -d '\n'`. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12` file. |
| `APPLE_NOTARY_API_KEY` | Contents of a **team** App Store Connect API key `.p8` file. Individual API keys cannot use `notarytool`. |
| `APPLE_NOTARY_KEY_ID` | Key ID for that API key. |
| `APPLE_NOTARY_ISSUER_ID` | Issuer ID for that API key. |

Keep these credentials out of the repository. A missing secret or failed notarization stops publication, so the workflow never labels an unnotarized build as a public release. The changelog starts without a version entry; add `0.1.0` after configuring the secrets to publish the first build.

## License

CherryTools is released under [the Unlicense](UNLICENSE). Anyone may use, modify, redistribute, or sell it without attribution requirements. Made by Shaik Jaleel in Muscat.
