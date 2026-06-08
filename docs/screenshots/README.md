# Screenshots

Drop PNG screenshots here matching the filenames the main README
references. Keep them under ~500 KB each; resize to ~1200 px on the
long edge so the grid in the README renders nicely.

| File | What it should show | Source |
|---|---|---|
| `web-ui.png` | The local web UI (`python webui.py`) with a real photo loaded so the dithered preview + sliders are both visible. | Captured via Playwright against a tall viewport. |
| `ios-home.png` | The iOS app's `HomeView` — status pill at the top, "Choose Photos" CTA centered, debug log tail at the bottom. | Captured from the iOS Simulator via `xcrun simctl io booted screenshot`. |
| `ios-preview.png` | The iOS app's `PreviewView` mid-edit — dithered preview at the top, brightness / contrast / rotation button groups below, Print CTA visible. | Same as above; reached by pre-staging a JPG into the app container's `Documents/` and using a temporary `--screenshot-mode` launch arg. |
| `ios-share.png` | The iOS Share Sheet with "Peripage" visible as a share target — proves the Share Extension is registered. | Captured by presenting `UIActivityViewController` programmatically (temporary `--show-share-sheet` flag), then cropping the resulting screenshot to the sheet portion. |
| `mac-app.png` | The Mac target running, ideally `PreviewView` so it's clear the iOS app builds cleanly to "My Mac". | Build `Peripage` for macOS in Xcode, launch, take a window screenshot with `Cmd + Shift + 4` then Space, then click the window. |

Optional extras you can add as a stretch:

| File | What it should show |
|---|---|
| `finder-quick-action.png` | Right-click on an image in Finder → Quick Actions → "Print to Peripage" menu item. |
| `print-output.jpg` | A photo of an actual print coming out of the Peripage — surprisingly more persuasive than any UI screenshot. |

If you add a `print-output.jpg`, consider also dropping `![](docs/screenshots/print-output.jpg)` right under the README's project title for hero-image impact.
