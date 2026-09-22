# TipTrack3r 1.3 screenshots

18 native iPhone 16 Pro PNG screenshots, 1206 × 2622 pixels. All job names, hours, tips, and totals are fictional. Images are unedited captures of the current app UI, without simulator chrome.

Recommended lead images: 02-dashboard-month-light.png, 03-dashboard-dark.png, 04-log-shift-light.png, 08-calendar-light.png, 10-history-light.png, and 14-siri-shortcuts-light.png.

Included: dashboard, shift entry, inline checkout-slip controls, calendar, history, settings, Siri help, jobs, welcome guide, weekly breakdown, and shift editor. The checkout-slip images show the selection controls, not a recognized receipt. These are still images, not animation recordings or Siri invocation captures.

## Safe demo setup

Separate simulator: TipTrack Screenshot Studio (15E86CCB-F846-4231-B091-9A71693E4744).

The DEBUG simulator-only `TIPTRACK_SCREENSHOT_DEMO=1` launch environment creates an in-memory database, seeds fictional jobs and shifts, and disables cloud sync, backups, and Spotlight in this separate simulator. It is excluded from release builds. Original simulator and phone records were not modified. The demo resets to its sample records on each launch with that environment variable; launching without it does not seed records.

To relaunch the existing demo:

```sh
env SIMCTL_CHILD_TIPTRACK_SCREENSHOT_DEMO=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch --terminate-running-process 15E86CCB-F846-4231-B091-9A71693E4744 atm.TipTrack
```
