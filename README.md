# VimItAll

![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![Release](https://img.shields.io/github/v/release/nkapila6/vimitall)

Vim mode for every macOS text field. Open-source, system-wide.

Uses the macOS Accessibility API to read and manipulate text directly in native apps, and falls back to synthesizing keyboard events for apps that don't expose Accessibility (Firefox, Chrome, Electron, etc.).

## Requirements

- macOS 14.0+
- Accessibility permission (System Settings > Privacy & Security > Accessibility)

## Build

```sh
xcodegen generate
xcodebuild -project vimitall.xcodeproj -scheme vimitall -configuration Debug build
```

Or use the build script (builds, resets Accessibility permission, launches):

```sh
./build.sh
```

## Install from release

1. Download the latest DMG from [releases](https://github.com/nkapila6/vimitall/releases)
2. macOS will block it with "Apple could not verify..." - strip the quarantine flag:

```sh
xattr -cr ~/Downloads/vimitall-*.dmg
open ~/Downloads/vimitall-*.dmg
```

3. Drag VimItAll to /Applications
4. Strip the quarantine flag from the app too:

```sh
xattr -cr /Applications/vimitall.app
open /Applications/vimitall.app
```

5. Grant Accessibility permission in System Settings > Privacy & Security > Accessibility

## Keybindings

### Motions

| Key | Action |
|---|---|
| `h` `j` `k` `l` | Move left/down/up/right |
| `w` `b` `e` | Next/prev word, end of word |
| `W` `B` `E` | Next/prev WORD, end of WORD (whitespace-separated) |
| `0` `$` | Start/end of line |
| `gg` `G` | Start/end of document |
| `f{char}` `F{char}` | Find char forward/backward on line |
| `t{char}` `T{char}` | Move to just before/after char on line |
| `;` `,` | Repeat last find, repeat reversed |

### Operators

| Key | Action |
|---|---|
| `x` `X` | Delete char under/before cursor |
| `dd` | Delete line |
| `yy` | Yank line |
| `p` `P` | Paste after/before |
| `D` | Delete to end of line |
| `C` | Change to end of line |
| `cc` `S` | Change whole line |
| `J` | Join lines |
| `u` | Undo (Cmd+Z) |
| `r{char}` | Replace char under cursor |
| `.` | Repeat last change |

### Operator + motion

| Key | Action |
|---|---|
| `dw` `dW` `db` `de` | Delete word/WORD/back/end |
| `d$` `dG` `dgg` | Delete to end of line/document/start |
| `cw` `c$` | Change word/to end of line |
| `yw` `y$` | Yank word/to end of line |

### Mode switching

| Key | Action |
|---|---|
| `esc` | Insert to Normal |
| `i` `a` `A` `I` | Insert at cursor/after/end of line/start of line |
| `o` `O` | Open line below/above |
| `s` | Delete char, insert |
| `v` `V` | Visual mode (char-wise / line-wise) |

### Visual mode

| Key | Action |
|---|---|
| `h j k l w b e` | Extend selection |
| `0` `$` `gg` `G` | Extend to line start/end, document start/end |
| `d` `x` | Delete selection |
| `y` | Yank selection |
| `c` | Change selection |
| `esc` | Exit visual |

### Counts

Numeric prefixes work with motions and operators: `5j`, `3w`, `2dd`, `3x`.

## Two strategies

- **AX strategy** (TextEdit, Notes, Safari, native apps): reads text and caret via Accessibility API. Accurate.
- **Keyboard fallback** (Firefox, Chrome, Electron, terminals): synthesizes arrow keys and shortcuts. Works everywhere, approximate.

The app auto-switches based on whether the focused element exposes editable text via Accessibility.

## App exceptions

Apps that have their own Vim mode (VS Code, IntelliJ, Neovim, terminals) are blacklisted by default. Add or remove apps via Preferences (menu bar icon > Preferences > App Exceptions). Browse the /Applications folder to add apps by name.

## Preferences

Open Preferences from the menu bar icon. Settings are organized into four sections:

### General
- Enable/disable vimitall
- Start at login (via SMAppService)
- Mode entry key: `esc`, `jk`, `Ctrl+[`, or a custom two-letter sequence

### Display
- Menu bar indicator: colored dot showing N (normal), I (insert), V (visual), D (disabled). Falls back to a neutral icon when disabled.
- Focus highlight: draws a colored border around the active window in Normal or Visual mode

### Strategy
- Keyboard fallback for unsupported apps: uses simulated arrow keys when Accessibility text access is unavailable

### App Exceptions
- Blacklist apps that have their own Vim mode (VS Code, IntelliJ, Neovim, terminals are excluded by default)
- Add apps by browsing /Applications or by bundle ID
- Remove apps from the list

## Architecture

```
Sources/
  App/            Entry point, event dispatch, app blacklist, login service
  Accessibility/  AXUIElement wrappers for text read/write
  KeyCapture/     CGEventTap, key sequence parser, keyboard synthesizer
  Vim/            State machine, motions, operators, mode handlers
  UI/             Menu bar status icon, focus highlight
  Preferences/    SwiftUI preferences window with sidebar
Tests/            Motion and state machine tests
```

## Limitations

- `f/F/t/T` only work in AX mode (need text access)
- `.` repeat is approximate
- Counts on operator+motion (`d2w`) not supported yet
- Word motions in keyboard fallback use macOS option+arrow (slightly different from Vim)
- No visual block mode (Ctrl-V)
- Custom mode-entry sequences should be 2 characters for best UX
- Start at login requires the app in /Applications with proper signing

## License

MIT