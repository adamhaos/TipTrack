# State machines in TipTrack3r

Where the app models "which state is this in", and the rule for adding more.

**Rule:** when two or more flags or optionals describe one thing, and only some
combinations make sense, use one enum. Put the user-facing wording on the enum
(`message`, `needsAttention`), not at the call sites. Keep existing computed
`Bool`s as shims only where many call sites read them.

## Explicit states

| Thing | Type | Where | States |
|---|---|---|---|
| App launch | `AppStartup` | TipTrackApp.swift | `ready(container)`, `failed(reason)` |
| Watch link (phone side) | `WatchSyncService.Connection` | WatchSyncService.swift | `notPaired`, `appNotInstalled`, `away`, `connected` |
| Face ID attempt | `PrivacyManager.AuthAttempt` | PrivacyManager.swift | `idle`, `inProgress`, `failed(message)`. `unlocked` stays a separate Bool on purpose, so re-checking while unlocked never hides the screen. |
| Checkout slip scan | `ReceiptScannerView.ScanPhase` | ReceiptScanner.swift | `empty`, `reading(image, scanID)`, `unreadable(image?)`, `read(result)`. Only the newest pick and the newest `scanID` may finish. |
| CSV import note | `ImportCSVView.ImportStatus` | ImportCSVView.swift | `info`, `problem`. Problems always show in red. |
| Schedule feed refresh, per job | `FeedRefreshStatus` | ScheduleStore.swift | `refreshed`, `partial`, `failed(keptPrevious:)` |
| Calendar day popover | `quickActionDay: Date?` | ShiftCalendarView.swift | nil = closed, otherwise the open day |
| Undo toast | `undoableShift: Shift?` | LogAndTotalsView.swift | nil = hidden, otherwise the shift Undo deletes |
| Live timer | `LiveShiftManager.current` | LiveShiftManager.swift | nil = no shift running |
| iCloud sync status | `CloudSyncStatus` | CloudSyncStatus.swift | owned by the sync work; see that file |

## Still implicit (planned)

- Dashboard top panel in LogAndTotalsView: `isShowingSettings`, `isShowingHistory`,
  `isShowingCalendar`, `isClosingTopPanel`, `pendingTopPanelOpen`,
  `isTopPanelExpanded`. Target: one `TopPanel` value (which panel, open/closing,
  compact/expanded).
- `AppRoute` (lower priority): five `UUID?` request tokens plus `event`/`logDate`/`logJobID`.
  Target: one typed pending route.

## Coalescing loops (intentionally left as is)

`ScheduleStore.refresh` and `scheduleReminders` use a running flag plus a
"pending" flag so a request made mid-run triggers one more pass. That pattern is
correct and small; don't fold it into an enum.
