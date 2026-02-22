# Inline Settings: Move DerivedData Path Into Popover Footer

## Problem

Settings opens a separate tiny floating window for a single text field. The "leave blank to use default" UX is confusing — users see the default path displayed but don't understand what blank means. The settings window feels disconnected from the popover.

## Design

Eliminate the Settings window. Show the DerivedData path inline as a permanent footer in the popover.

### Layout

```
┌─────────────────────────────────────────┐
│ KGB  Known Good Build                   │
│─────────────────────────────────────────│
│                                         │
│  (commands list / empty state / error)  │
│                                         │
│─────────────────────────────────────────│
│ ~/Library/.../DerivedData       [Change]│
└─────────────────────────────────────────┘
```

### Footer behavior

- Always visible at bottom of popover, below a divider
- Shows current DerivedData path, tilde-abbreviated and truncated
- "Change" button opens `NSOpenPanel` folder picker
- On selection: writes to `@AppStorage("derivedDataPath")`, calls `derivedDataAccess.checkAccess()`

### States

**Working (hasAccess = true):**
- Path text in `.secondary` color
- Main content shows commands as normal

**Error (hasAccess = false):**
- Path text in `.red`
- Main content area shows "DerivedData not found" message (existing pattern, minus the SettingsLink button)
- Change button remains available in footer — the fix is right there

### Deletions

- `SettingsView.swift` — entire file
- `Settings { SettingsView() }` scene from `KGBApp.swift`
- All `SettingsLink` references in `PopoverView.swift` (header gear icon + "Open Settings" button)

### Files changed

| File | Action |
|------|--------|
| `KGB/KGB/Views/PopoverView.swift` | Add footer, remove SettingsLinks |
| `KGB/KGB/Views/SettingsView.swift` | Delete |
| `KGB/KGB/KGBApp.swift` | Remove Settings scene |
