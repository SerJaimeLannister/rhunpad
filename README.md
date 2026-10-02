# rhunpad

A minimal, local-first scratchpad for quick notes — plain Markdown files in a folder you choose. Built on [rhun](https://github.com/vshvedov/rhun) by Vlad Shvedov (MIT License); rhunpad is a streamlined fork focused on note capture.

- **Quick capture:** `⌘N` / `Ctrl+N` starts a new note instantly, named `untitled-1.md`, `untitled-2.md`, …
- **Nothing to manage:** notes are just files in your folder. Empty notes delete themselves when closed; notes with text are kept.
- **Autosave:** edits save to disk automatically (about a second after you stop typing), with a subtle *Saved* / *Save failed* status.
- **Fast:** no cloud, no accounts, no indexing — the app opens ready to type.

## Requirements (macOS)

- macOS 12 or later on Apple silicon
- Xcode Command Line Tools:

```sh
xcode-select --install
```

(This provides `clang`, `as`, `codesign`, and the rest of the toolchain. Python 3 is also needed for the build's source translation.)

## Build the production app

```sh
./build-macos.sh
```

This produces `build/rhunpad` (the executable) and `build/rhunpad.app` (the app bundle). The build script checks for the required tools and tells you what is missing.

## Install

```sh
./install-macos.sh
```

Installs `rhunpad.app` into `/Applications` when writable, otherwise into `~/Applications` (created if needed). An existing installation is replaced. Launch with:

```sh
open /Applications/rhunpad.app
```

## First launch: choose your notes folder

The first time rhunpad starts it asks where your notes should live:

1. A folder picker opens. Navigate with the arrow keys — `Enter` goes into a folder, `../` goes up a level; the current path is shown in the input field.
2. Pick a folder with the **Choose <folder>** row, or type a new name and press `Enter` to create it.
3. The choice is remembered in `~/.config/rhunpad/config` (`notes_folder`), and every later launch opens that folder directly — no repeated asking.

If you cancel the picker, no notes or folders are created; the welcome screen offers **Choose notes folder** (also `⌘T` / `Ctrl+T`) to try again as often as you like. If the saved folder later disappears (unmounted drive, moved directory), rhunpad says so and asks you to choose again.

## Change the notes folder

1. Open Settings: `⌘,` / `Ctrl+,`.
2. Under **Files**, the **Notes folder** row shows the current folder; click **Change Folder**.
3. Pick a new folder in the picker. If the old folder still has notes, rhunpad asks explicitly:
   - **Move Notes** — moves the old notes into the new folder (name collisions are left in place, never overwritten), or
   - **Use New Folder** — leaves old notes where they are.
4. The new folder is remembered on the next launch.

Nothing is moved or deleted without one of those explicit choices.

## Troubleshooting

- **A folder can't be opened / notes don't save:** the folder may lack permissions, or live on an unavailable drive. Pick a different folder via Settings → Change Folder.
- **Cancelled the first-launch picker:** fine — press `⌘T` / `Ctrl+T` or click *Choose notes folder* on the welcome screen and try again. Cancel is never treated as a choice.
- **Missing build tools:** run `xcode-select --install`, then `./build-macos.sh` again.
- **Signing/notarization:** the built app is *ad-hoc signed* only — it is **not** notarized and carries no Developer ID. Because it is built locally it runs without Gatekeeper prompts on this machine, but if you copy it to another Mac you may need to right-click → *Open* once, or re-sign with your own certificate. For personal use this is normally invisible.

## Development

Run the editor directly from the build output, including the headless test harness:

```sh
./build-macos.sh          # or: tools/build-mac.sh
build/rhunpad             # run in place
tests/ui.sh               # headless UI suite
python3 tests/desktop-ux.py
```

The development binary and the production app are the same program (`PAD_DEBUG` is 0 in the source: the folder is asked for once, then remembered; deleting the saved `notes_folder` line in `~/.config/rhunpad/config` resets the first-launch question).

The rest of the rhun feature set (terminal, git, fuzzy search, agents panel) is still in the codebase; this fork's surface is the scratchpad above. Linux and Windows build through the upstream `build.sh` / `tools/build-windows.py` paths.
