# CherryTools

CherryTools is a native Apple Silicon macOS menu bar utility for inspecting ports, keeping clipboard history, cutting files in Finder, and running quick Mac fixes. It requires macOS 14 or later and has no Dock icon.

## Features

- **Ports:** See listening TCP ports and optionally UDP sockets, and whether each port is local-only or reachable from the network. Search by port, process, project, user, or PID; filter by runtime; inspect process details; and terminate a process after confirmation. **Show all** includes system processes visible to your account and is on by default. CPU, memory, and power values come from macOS process counters. CPU and power appear after a second sample.
- **Clipboard:** Off until you turn it on. Keep copied text and images locally for up to 30 days; copied files are saved as links to their location. Press **Control–Option–V** to open history, use the arrow keys or the pointer to choose an item, and press **Return** to copy it again. You can pause saving and exclude apps. Items that apps mark as private, such as passwords, are never saved.
- **Finder cut:** Press **Command–X** in Finder to mark selected files for moving, then **Command–V** in Finder to move them. Text fields such as rename and search keep normal Cut and Paste. This requires Accessibility permission. You can also right-click files in Finder and choose **Cut with CherryTools**, then right-click a destination folder and choose **Move Cut Files Here**; these menu items do not need Accessibility permission and never replace existing files. macOS may show them under **Services** or **Quick Actions**, and you can manage them in System Settings → Keyboard → Keyboard Shortcuts → Services. CherryTools plays macOS's built-in Tink sound once files are ready to move; you can turn it off in Settings.
- **Toolbox:** Quick fixes for your Mac. **Flush DNS Cache** clears saved website addresses after macOS asks for your administrator password.
- **Settings:** Configure launch at login, menu bar icon visibility, the menu bar port count, clipboard history, and Finder cut. Right-click the menu bar icon for quick actions. **Control–Option–Command–M** restores a hidden menu bar icon, and opening CherryTools again also shows the panel.

## Install

Download the latest ZIP from [Releases](https://github.com/iamsj7/Cherry-macOS/releases), then drag `CherryTools.app` to your Applications folder. Each release includes full install steps. Builds that are not yet notarized by Apple are marked as pre-releases and need a one-time approval in System Settings.

## Build and run

Install Xcode and its command line tools on an Apple Silicon Mac, then run:

```sh
./scripts/build-app.sh
open dist/CherryTools.app
```

The script builds an arm64 app bundle and signs it locally. Set `CODESIGN_IDENTITY` to sign with a certificate instead of an ad hoc signature. Quit any running CherryTools copy before opening a new build. The bundle identifier is `com.shaikjaleel.cherrytools`.

To build, sign with your Apple Development certificate if you have one, and install to `/Applications`:

```sh
./scripts/install-app.sh
```

A certificate keeps the app's identity stable, so macOS keeps its Accessibility permission across rebuilds. Ad hoc builds must be granted it again after each rebuild.

Run the tests with:

```sh
swift test
python3 tests/test_release_notes.py
```

To use Finder cut, open **CherryTools → Settings → Shortcuts**, grant Accessibility access in System Settings, then return to CherryTools. The shortcut turns on when you come back.

After changing `Resources/CherryToolsIcon.png`, run `swift scripts/make-icons.swift` and `iconutil -c icns Resources/CherryTools.iconset -o Resources/CherryTools.icns`.

## Data and permissions

Clipboard history stays on this Mac in `~/Library/Application Support/CherryTools/Clipboard`. The folder is readable only by your account and is excluded from Time Machine, but its contents are not encrypted. While history is on and not paused, CherryTools checks for clipboard changes every 1.5 seconds. It skips items marked with the [nspasteboard.org](http://nspasteboard.org) concealed, transient, or auto-generated types, and copies made while an excluded app is frontmost. Password apps are excluded by default.

CherryTools reads ports and process details from macOS directly every eight seconds while the Ports panel is open; the optional menu bar count refreshes every 30 seconds. macOS may restrict information about other users' or protected processes, and may refuse to terminate them. Project names inside Desktop, Documents, and Downloads are read only if you turn that on in Settings, because it can prompt for folder access. CherryTools asks for administrator privileges only when you choose **Flush DNS Cache**. macOS shows the password prompt, and CherryTools never sees your password.

Finder cut sees key presses sent to Finder only. Keys typed in other apps never reach it.

A locally signed bundle is for development and personal installation. Apple requires Developer ID signing and notarization for a downloadable app to open without a Gatekeeper warning.

## GitHub Releases

Add a versioned entry at the top of [CHANGELOG.md](CHANGELOG.md) and push it to `main`:

```md
## [0.1.0] - 2026-10-03

- Initial public release.
```

The [CI workflow](.github/workflows/ci.yml) tests and builds every push to `main` and every pull request without signing. The [release workflow](.github/workflows/release.yml) runs on an Apple Silicon GitHub runner whenever `CHANGELOG.md` changes on `main`. It reads the newest version, skips versions that already have a Git tag, runs the tests, builds an arm64 app, and publishes a ZIP and SHA-256 checksum as a GitHub Release. The changelog entry and the install guides in [.github/release](.github/release) become the release notes. The app version inside the ZIP comes from the heading. You can rerun the workflow manually from the Actions tab after fixing a failed run.

Without signing secrets, the workflow publishes an unnotarized build, marked as a pre-release, with install steps for approving it in System Settings. To publish notarized releases, add these repository Actions secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 text of an exported **Developer ID Application** `.p12` certificate and private key. On macOS: `base64 < certificate.p12 | tr -d '\n'`. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12` file. |
| `APPLE_NOTARY_API_KEY` | Contents of a **team** App Store Connect API key `.p8` file. Individual API keys cannot use `notarytool`. |
| `APPLE_NOTARY_KEY_ID` | Key ID for that API key. |
| `APPLE_NOTARY_ISSUER_ID` | Issuer ID for that API key. |

Keep these credentials out of the repository. If only some secrets are set, or notarization fails, nothing is published.

## License

CherryTools is released under [the Unlicense](UNLICENSE). Anyone may use, modify, redistribute, or sell it without attribution requirements. Made by Shaik Jaleel in Muscat.
