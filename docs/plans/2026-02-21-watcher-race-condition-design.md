# Watcher Race Condition — Design

**Date:** 2026-02-21
**Status:** Approved

## Problem

FSEvents fires the instant an `.xcresult` bundle appears on disk, but Xcode hasn't finished writing the contents yet. `xcresulttool get build-results` returns truncated JSON, causing `ParseError.invalidJSON`. The result is silently dropped and never appears in the popover.

**Evidence:** 100% reproducible on watchOS Cmd+R. Manual `xcresulttool` call seconds later succeeds. Initial scan on app launch works because bundles are fully written by then.

## Solution: Retry with Pending UI State

### Data Flow

1. FSEvent fires → watcher callback with xcresult path
2. Parse scheme name from filename (available immediately, no xcresulttool needed)
3. Add a **pending entry** to `CommandStore` with scheme name + xcresult path
4. Popover shows spinner row: `[spinner] SchemeName — waiting for Xcode... [Retry Now]`
5. Background: attempt extraction every 5 seconds, up to 60 seconds (12 attempts)
6. On success → replace pending entry with real `BuildCommand`, cancel retry loop
7. On all retries exhausted → show `SchemeName — could not read result`
8. "Retry Now" button → immediately triggers an extraction attempt
9. On successful extraction (from either retry or Retry Now), cancel the backoff — no further polling

### Architecture Decisions

**Retry lives in AppDelegate callback.** The watcher's job is detection. The extractor's job is parsing. The callback is where the error is currently swallowed — that's where retry belongs. No new wrapper types.

**Only retry on `ParseError.invalidJSON`.** Other errors (malformed filename, no project found) are not transient. Fail immediately on those.

**Polling interval: 5 seconds.** Generous enough to not waste `xcresulttool` calls. The "Retry Now" button gives users an escape hatch for faster resolution when they know the build is done.

**Timeout: 60 seconds.** If an xcresult isn't readable after 60 seconds, something else is wrong. The existing initial scan on next app launch will catch it anyway.

### Components Changed

| Component | Change |
|-----------|--------|
| `CommandStore` | New concept: pending entries (scheme name + xcresult path, no destination yet). New methods: `addPending()`, `resolvePending()`, `failPending()`. |
| `AppDelegate` callback | Adds pending entry on detection, kicks off retry loop with cancellation support. |
| `PopoverView` / `CommandRowView` | New pending row variant: spinner + scheme name + "waiting for Xcode..." + "Retry Now" button. Failed state variant for exhausted retries. |
| `DerivedDataWatcher` | Unchanged |
| `CommandExtractor` | Unchanged |
| `XCResultParser` | Unchanged |

### What We're NOT Doing

- No reverse-engineering xcresult bundle internals for a "done" signal
- No learned timing / stored build durations
- No debouncing or delays in the watcher itself
- No new wrapper types around CommandExtractor

### Logging

- Each retry attempt: `.debug` level — `"Retry N/12 for <path>, waiting 5s"`
- Successful extraction after retry: `.info` level — `"Extracted <scheme> after N retries"`
- All retries exhausted: `.warning` level — `"Failed to extract <path> after 12 attempts"`
