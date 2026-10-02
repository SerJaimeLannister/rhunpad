# rhunpad

A minimal, local-first scratchpad for quick notes — plain Markdown files in a folder you choose. Built on [rhun](https://github.com/vshvedov/rhun) by Vlad Shvedov (MIT License); rhunpad is a streamlined fork focused on note capture.

## What rhunpad is

- **A folder of Markdown files you own.** Notes are ordinary `*.md` files in one folder of your choosing — sync it, back it up, grep it, edit it anywhere else. rhunpad adds no database, no lock-in, no hidden state.
- **Quick capture:** `⌘N` / `Ctrl+N` starts a new note instantly, named `untitled-1.md`, `untitled-2.md`, … The name is written when the note first saves; a note you typed in is kept, an empty one deletes itself when closed.
- **Autosave:** edits save to disk automatically (about a second after you stop typing), with a subtle *Saved* / *Save failed* status. Session restore reopens your open notes on the next launch.
- **Fast and quiet:** no cloud, no accounts, no indexing, no AI, no plugins — the app opens ready to type.
- **One decision, made once:** where notes live. rhunpad asks for the notes folder on the very first launch — before the editor appears — and remembers it after that.

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

Installs `rhunpad.app` into `/Applications` when writable, otherwise into `~/Applications` (created if needed), and puts a `rhunpad` command in `~/.local/bin`. An existing installation is replaced. If `~/.local/bin` is not on your PATH, the installer prints how to add it (`fish_add_path ~/.local/bin` in fish). Launch with either:

```sh
rhunpad                      # terminal command (starts the app)
open /Applications/rhunpad.app
```

## First launch: choose your notes folder

The first time rhunpad starts — before any editor or note appears — it asks where your notes should live, with the **native macOS folder-selection dialog**:

1. The dialog opens at your **home folder**. Browse to wherever you keep (or want) your notes.
2. Select a folder and press **Choose** (or double-click the folder).
3. The choice is written to `~/.config/rhunpad/config` (`notes_folder`) and every later launch opens that folder directly — it is never asked again while the setting holds.

Notes about the first-launch flow:

- **Cancel is never a choice.** If you cancel the dialog, no notes or folders are created and no setting is written; the welcome screen offers **Choose notes folder** (also `⌘T` / `Ctrl+T`) so you can try again as often as you like.
- **A missing folder asks again.** If the saved folder later disappears (unmounted drive, moved directory), rhunpad says so and asks you to choose again — nothing is silently recreated.
- **Resetting the question:** deleting the `notes_folder` value (or the line) in `~/.config/rhunpad/config` makes the next start ask again. An empty value means "ask at the next start".

## Change the notes folder

1. Open Settings: `⌘,` / `Ctrl+,`.
2. Under **Files**, the **Notes folder** row shows the current folder; click **Change Folder** — the same native folder dialog opens, starting at the current folder.
3. Pick a new folder. If the old folder still has notes, rhunpad asks explicitly:
   - **Move Notes** — moves the old notes into the new folder (name collisions are left in place, never overwritten), or
   - **Use New Folder** — leaves old notes where they are.
4. The new folder is remembered on the next launch.

Nothing is moved or deleted without one of those explicit choices.

## Configuration

`~/.config/rhunpad/config` is a plain INI file, also editable from Settings (`⌘,`) while the app runs — changes are picked up live. Notable keys:

| Key | Meaning |
| --- | --- |
| `notes_folder` | Where notes live. Empty asks at the next start. |
| `autosave` | Save edits automatically after a pause (default on). |
| `restore_session` | Reopen the notes you had open on launch (default on). |
| `font_size`, `line_height`, `word_wrap`, `vim_mode`, … | Editor options in Settings. |

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

The development binary and the production app are the same program (`PAD_DEBUG` is 0 in the source: the folder is asked for once, then remembered; deleting the saved `notes_folder` line in `~/.config/rhunpad/config` resets the first-launch question). Headless runs (`--headless`, used by the test scripts) never show a dialog: they fall back to `~/rhunpad` as the notes home, overridable with `RHUNPAD_HOME`.

The rest of the rhun feature set (terminal, git, fuzzy search, agents panel) is still in the codebase; this fork's surface is the scratchpad above. Linux and Windows build through the upstream `build.sh` / `tools/build-windows.py` paths — there the platform has no native folder dialog yet, so the in-app folder browser is used instead.
