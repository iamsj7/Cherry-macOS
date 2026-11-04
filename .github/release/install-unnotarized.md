
## Install

> [!IMPORTANT]
> This pre-release is **not notarized by Apple**, so macOS blocks it the first time you open it. Only continue if you trust this repository. It is built from the tagged source by GitHub Actions, and you can [build it yourself](#build-from-source) instead.

Requires a Mac with Apple silicon and macOS 14 or later.

1. Download `CherryTools-*-macOS-arm64.zip` from **Assets** below.
2. Open the ZIP.
3. Drag `CherryTools.app` to your Applications folder.
4. Open CherryTools. macOS says it can't verify the app. Click **Done**.
5. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to CherryTools.
6. Click **Open Anyway** again and enter your password if asked.

CherryTools has no Dock icon, so look for it in the menu bar. You only need to do this once for each version. After updating, macOS may also ask you to allow Accessibility access again.

## Build from source

Install Xcode, then run:

```sh
git clone https://github.com/iamsj7/Cherry-macOS.git
cd Cherry-macOS
./scripts/install-app.sh
```
