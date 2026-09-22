# TipTrack 1.4 stress check — October 9, 2026

The app was reviewed and exercised in an isolated iPhone 16 Pro simulator running iOS 27.0. Demo records used an in-memory database with cloud syncing, automatic backups, and Spotlight disabled. The regular simulator and real saved shifts were not used for destructive tests.

## Bugs corrected

- Calendar month navigation now keeps the selected day in the displayed month, including short months and leap years. Selected-day totals come from the live records rather than only the visible grid.
- Busy calendar days now page their entries in small groups. A 37-entry day and a six-week month fit the calendar panel without vertical scrolling. Schedule Status opens separately so it cannot push the calendar offscreen.
- Calendar amounts, long job names, dashboard totals, and Recents cards fit better at larger text sizes. Compact Recents measures its content height and uses a single column for larger text.
- Job edits, default-job changes, shift deletion/restoration, and save Undo report persistence failures and roll back failed changes.
- Receipt replacement keeps the previous attachment until the new image and model changes both save. Failed saves and successful save Undo remove newly created receipt files.
- Ending a timer closes a top panel before opening its draft and keeps the timer's job selection.
- Duplicate/unknown stored dashboard card IDs no longer create duplicate cards. Removed obsolete ordering state and unused summary UI.
- Checkout scanning remains inline below its button. It pushes the keypad down, expands the panel upward within its height limit, and scrolls the recognized draft into view. Removed the full-height spacer that created the large blank area. Attaching a scan returns to the normal form and keypad.

## Simulator checks

| Area | Observed result |
| --- | --- |
| Shift entry and save Undo | Credit $250.75, cash $50, tip-out $10 added $290.75; Undo restored the original totals. |
| Toast photo scanning | Synthetic slip with “Cash Tips: $300.00” and “OWED TO MORGAN: $92.50” used $92.50 as cash; credit $250 and bar tip-out $25 were correct. |
| Attach, save, Undo | Scanned entry added $317.50; immediate Undo restored weekly $711.25 and monthly $1,493.50. Receipt-file set matched its pre-save state. |
| Calendar navigation | Previous month, Today, selected-day totals, and day-page controls worked. A 37-entry day remained accessible through paging. |
| Calendar layout | Six-week August and larger text fit without vertical scrolling. |
| Dashboard navigation | Month/week controls and their Today buttons operated independently. Repeated horizontal week-strip swipes did not open the calendar accidentally. |
| Recents | Compact/expanded panels, older weekly/monthly groups, and week breakdown navigation worked. Large-text cards remained fully visible. |
| Shift edit/delete/restore | Negative input was rejected with the draft retained; a valid edit updated totals; deletion and restoration updated the visible records and totals. |
| Jobs | Cancelling an edit preserved the original job; changing the default left one default job. |
| Appearance | Light and dark layouts inspected; normal and larger text exercised. |

## Automated checks

All four standalone suites passed: Siri rules, release/data checks, receipt parsing, and navigation/layout-data rules. Coverage includes preferred week starts, DST, privacy gates, hourly averages, CSV round trips, duplicate imports, invalid amounts, localized numbers, recurring schedules, arbitrary Toast names, month-end selection, leap years, busy-day pagination, and dashboard preference deduplication.

Debug simulator and unsigned Release device builds passed for the app and extension targets with no compiler warnings or errors in the final build logs. All six target/configuration marketing-version entries are 1.4. Whitespace validation passed.

## Limits

This is a broad source and simulator check, not a guarantee that every bug is eliminated. Real camera capture, spoken Siri interactions, Face ID, multi-device iCloud sync, and notification delivery still require physical-device checks. Those integrations were not fully validated in this simulator run. Save-failure rollback paths were reviewed; actual disk-full/database-failure conditions were not injected.

## Evidence

- [Regression check output](checks.log)
- [Final build results](build-results.txt)
- [Six-week calendar with larger text](calendar-six-weeks-large-text.png)
- [Recents with larger text](recents-large-text.png)
