# vimitall

Vim mode for macOS text fields. An open-source clone of kindaVim.

**Status: early WIP.** Basic motions and operators work via Accessibility API. Not yet ready for daily use.

## Requirements

- macOS 14.0+
- Accessibility permission (System Settings > Privacy & Security > Accessibility)

## Build

```sh
xcodegen generate
xcodebuild -project vimitall.xcodeproj -scheme vimitall -configuration Debug build
```

## MVP Move Set

### Motions
h, j, k, l, w, b, e, 0, $, gg, G

### Operators
x (delete char), dd (delete line), yy (yank line), p (paste after), u (undo via Cmd+Z)

### Insert triggers
i, a, o, O, esc (or jk)

### Counts
Numeric prefixes work with motions and operators (e.g., 3w, 2dd).

## Architecture

- `Sources/Accessibility/` - AXUIElement wrappers for reading/writing text fields
- `Sources/KeyCapture/` - CGEventTap for global key capture and key sequence parsing
- `Sources/Vim/` - Vim state machine, motions, operators, key mappings
- `Sources/UI/` - Menu bar status item
- `Sources/Preferences/` - SwiftUI preferences window

## Roadmap

- Visual mode
- Text objects (iw, aw, etc.)
- f/t/F/T character search
- % for bracket matching
- Macros (q/@)
- . (repeat)
- Custom key mappings
