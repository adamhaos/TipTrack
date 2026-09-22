# TipTrack 1.4 bug check

Checked October 4, 2026.

Version 1.4 is set in Debug and Release for TipTrack, TipTrackWidgets, and TipTrackControls. The built production app and both embedded extensions were checked and each reports `CFBundleShortVersionString = 1.4`. The build number remains 1.

## Fixes

- Reject invalid, negative, nonfinite, and overflowing CSV amounts/hours/rates instead of importing corrupt earnings or silently replacing values.
- Preserve quoted job names containing commas, quotes, and newlines across CSV export/import.
- Skip duplicates inside a single import, recognize unassigned shifts, and include hours/rate in duplicate comparisons. Roll back failed imports.
- Validate shift edits, support decimal-comma input, show save failures, retain drafts on failure, and clear stale import fingerprints after editing.
- Use only shifts with recorded hours for the dashboard hourly average. Exclude the next week's boundary from the current week.
- Keep income ratio bars inside their available width when net cash is negative.
- Apply the selected week start to summary widgets and realign the dashboard week when that setting changes. Include base pay in the Tonight widget's typical earnings.
- Protect the earnings headline, CSV data tools, and share preview when earnings are locked. Refresh widget snapshots after privacy changes. Keep deep links pending while the app is locked, dismiss presented app screens when a locked app backgrounds, and avoid relocking during biometric authentication's inactive phase.
- Refresh Spotlight after data/settings changes and remove stale records. Match the Spotlight settings default to the app default.
- Refresh scheduled reminders after shifts change; serialize daily reminder updates to prevent overlapping changes from leaving stale reminders.
- Refresh all schedule widgets when schedules change. Preserve downloaded shifts during partial calendar-feed failures until a complete refresh succeeds.
- Allow the dashboard to scroll when its cards exceed available space. Split the dashboard view into smaller expressions so Swift compiles its added event handlers reliably.
- Set a newly added job's default flag when requested, restore omitted dashboard/week preferences during reset, and disable receipt draft use while scanning.
- Prevent yearly recurrence interval multiplication from overflowing for very large interval values.

## Verification

- Debug simulator build: passed for the app and both extensions, no compiler warnings/errors in the final log.
- Release iOS device build with signing disabled: passed for the app and both extensions, no compiler warnings/errors in the final log.
- `Tests/run-checks.sh`: passed all three suites.
  - Siri: periods, week preferences, DST, timed-shift averages, privacy conditions, and invalid inputs.
  - Release: real transient SwiftData models; CSV round trips, repeated imports, unassigned shifts, different hourly rates, invalid/overflowing numbers, localized edits, and calendar recurrence/exceptions including a very large yearly interval.
  - Receipts: the exact production parser compiled separately from its UI, using an opaque image stand-in; PosiTouch fields, label preference, continuation lines, decimal commas, and missing amounts.
- Isolated iPhone 16 Pro simulator with in-memory demo data: launch, dashboard rendering, numeric entry, save, updated totals, calendar day statistics, weekly breakdown, edit presentation, and rejection of a negative edit amount passed. Existing simulator data was not used. The temporary simulator was removed after checking.
- `git diff --check`: passed.

## Coverage limits

This is a broad code review plus targeted regression and simulator checks, not a guarantee that every interaction is bug-free. Real-device iCloud sync/migration, Face ID/background transitions, notification delivery, live activities, widgets/Control Center, spoken Siri requests, camera OCR, and real calendar-network failures still need device testing. The Xcode project has no configured test target; the standalone runner executes the checks described above. Production builds were not signed, archived, uploaded, or published.

Run the saved regression checks from the repository with `Tests/run-checks.sh`. SwiftData compilation requires Xcode's compiler services; run outside a restrictive sandbox or grant the required build access.

## Light-mode Log Shift follow-up

Removed the separate fixed-height top overlay and the overlapping inner dimmer. One stable dimming layer now covers the dashboard, navigation bar, and status bar, with the entry panel above it. This removes the horizontal gray seam shown in the reported screenshot. Debug build passed; opening and closing the panel and uniform light-mode dimming were checked visually in a separate demo simulator. Evidence: `light-mode-log-shift.png`.

## Dashboard spacing follow-up

Removed the dashboard's vertical scroll container at the user's request. Reduced card gaps from 6 to 4 points, dashboard top/bottom padding to 4/8 points, and weekly/monthly card and amount-tile vertical padding from 14 to 10 points. The complete dashboard, including Live Timer and Log Shift, fits on the iPhone 16 Pro at standard text size. Debug build passed and the layout was visually verified using demo data. This replaces the earlier decision to allow dashboard vertical scrolling. Evidence: `dashboard-fixed-spacing.png`.
