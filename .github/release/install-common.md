
## Set up CherryTools

1. Click the cherry icon in the menu bar. Right-click it for quick actions.
2. **Clipboard history** is off until you turn it on in the Clipboard tab.
3. **Finder ⌘X** needs Accessibility permission. Open **Settings → Shortcuts**, click **Enable Accessibility Access**, and turn on CherryTools in System Settings. You can use **Cut with CherryTools** in Finder's right-click menu without this permission.
4. **Flush DNS Cache** in the Toolbox tab asks for your administrator password each time. macOS shows the prompt, and CherryTools never sees your password.

Press **Control–Option–V** to open Clipboard from anywhere. If you hide the menu bar icon, press **Control–Option–Command–M** or open CherryTools again.

## Uninstall

1. Right-click the menu bar icon and choose **Quit CherryTools**.
2. Move `CherryTools.app` from Applications to the Trash.
3. To remove saved clipboard history, also delete `~/Library/Application Support/CherryTools`.

## Verify your download

In Terminal, go to the folder with both files and run:

```sh
shasum -a 256 -c CherryTools-*.sha256
```

The result should end in `OK`.
