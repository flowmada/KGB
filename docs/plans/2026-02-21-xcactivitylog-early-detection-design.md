# xcactivitylog Early Detection — Design

**Date:** 2026-02-21
**Status:** Approved

## Problem

xcresult bundles don't appear until the run/test session ends (user hits Stop or tests finish). Users see nothing in KGB after a build completes until that happens. Cmd+B builds never produce xcresults at all.

## Solution

Watch for `.xcactivitylog` files in `Logs/Build/` as an early signal. These appear immediately when the build finishes. Parse scheme + destination device name from the decompressed text. Show a pending entry in the popover right away. When the xcresult eventually appears (on Stop or test completion), upgrade the entry with full destination data and a working command.

## Data Flow

1. User hits Cmd+B/R/U → Xcode builds
2. Build finishes → `.xcactivitylog` appears in `Logs/Build/` → FSEvent fires
3. KGB decompresses the gzipped file, extracts scheme + destination from the `Workspace X | Scheme Y | Destination Z` line
4. Pending entry appears in popover with scheme name + device
5. **Cmd+B:** entry stays as build-only — shows "Run and stop to capture full command"
6. **Cmd+R:** user eventually hits Stop → xcresult appears in `Logs/Launch/` → FSEvent fires → KGB extracts full destination via xcresulttool → pending entry upgrades to real command with copy-to-clipboard
7. **Cmd+U:** tests finish → xcresult appears in `Logs/Test/` → same upgrade path

## Matching xcactivitylog to xcresult

When an xcresult arrives, match it to the pending entry by **scheme name**. The xcresult filename contains the scheme (`Run-PizzaCoachWatch-2026.02.21_...xcresult`), and the xcactivitylog has `Scheme PizzaCoachWatch`.

## PendingRowView States

Three states in one view:

1. **Waiting** — spinner + "Waiting for Xcode..." + "Retry Now" button. An xcresult is expected but hasn't appeared or isn't readable yet. Transitions to a real `CommandRowView` when xcresult is successfully extracted.
2. **Build only** — scheme + device visible, no full command. Shows "Run and stop to capture full command." Used for Cmd+B (no xcresult coming) and as fallback when xcresult retries exhaust.
3. **Failed** — couldn't parse the xcactivitylog at all. Something is actually wrong (corrupt file, format change). Surfaces the error so the user can report it.

## Components Changed

| Component | Change |
|-----------|--------|
| `DerivedDataWatcher` | Also fire callback for `.xcactivitylog` files in addition to `.xcresult` |
| `AppDelegate` callback | Route `.xcactivitylog` vs `.xcresult` to different handlers |
| New: `BuildLogParser` | Decompress gzipped xcactivitylog + extract scheme/destination from text. No Process calls — just `Data` gunzip + string search |
| `CommandStore` / `PendingExtraction` | Add destination device name field. Add state enum: `.waiting`, `.buildOnly`, `.failed`. |
| `PendingRowView` | Render three states: spinner/waiting, build-only with message, failed with error |
| `DerivedDataScanner` | Also scan `Logs/Build/` for xcactivitylogs on initial scan, not just xcresults in `Logs/Test` and `Logs/Launch` |
| `CommandExtractor` | Unchanged — still does xcresulttool extraction for xcresults |

## What We Keep From the Retry Work

Everything. The retry loop handles the narrow race when an xcresult appears but isn't fully written. The pending UI infrastructure is already built. This design adds an earlier trigger point via xcactivitylog detection.

## xcactivitylog Format

The file is gzip-compressed text with an `SLF0` header. Key extractable lines:

```
Workspace PizzaCoach | Scheme PizzaCoachWatch | Destination Apple Watch Series 11 (46mm)
Project PizzaCoach | Configuration Debug | Destination Apple Watch Series 11 (46mm) | SDK Simulator
```

Parsing: decompress with gunzip, search for the `Workspace ... | Scheme ... | Destination ...` line, split on ` | `.

## What We're NOT Doing

- Not replacing xcresulttool — xcresults remain the source of truth for full destination data (platform, device name, OS version)
- Not parsing the full SLF0 format — just searching for the summary line
- Not adding App Sandbox support (still need Process for xcresulttool)
