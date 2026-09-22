# TipTrack3r Siri integration

The App Intents integration exposes seven App Shortcuts: earnings queries, confirmed voice logging, shift entry, history, the calendar, and starting/ending a live timer. Jobs are App Entities and refresh in shortcut suggestions when jobs change or the app unlocks. All nine earnings periods use the app's chosen week start and exclude deleted shifts. Hourly averages exclude shifts without recorded hours.

Voice logging confirms the job, date, tips, tip-out, hours, hourly rate, and final earnings before inserting a shift. iOS 18 and later use action confirmation; iOS 17 confirms the selected job with the complete shift summary. Declining either confirmation exits before database insertion. These actions open the app so privacy authentication can run reliably. Local device authentication is required for earnings, voice saves, and timer actions. Job discovery cannot reveal jobs while the app is locked.

The existing database path, schema, bundle identifier, and CloudKit container are unchanged. The app shares its registered ModelContainer with Siri in the same process. Background access uses the existing store selection logic. Voice saves use a separate ModelContext so a failed save cannot roll back unrelated UI edits; successful saves refresh widgets and enabled daily CSV backups.

## Automated checks

From the repository root:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path /tmp/TipTrackSiriModuleCache TipTrack/TipTrackSiriRules.swift Tests/SiriRulesChecks.swift -o /tmp/TipTrackSiriRulesChecks
/tmp/TipTrackSiriRulesChecks
```

These checks use only test values. They cover time-period boundaries, custom week starts, daylight-saving transitions, hourly averages, privacy gates, empty entries, negative amounts, nonfinite values, and numeric overflow. The app build also validates App Intents metadata and App Shortcut phrases.

## iPhone verification

Spoken recognition and Face ID need an on-device check with Siri enabled. Settings → Siri, Widgets & Help lists example phrases.

1. Ask “How much did I make this week in TipTrack3r?” and compare with the dashboard. Repeat for last month and a specific job. Verify a period without shifts reports no shifts.
2. Ask “Log my tips in TipTrack3r.” Supply a job, credit and cash tips. Decline confirmation and verify history is unchanged. Confirm a separate entry and check its job, date, tips and total. Test hours and hourly pay using a Shortcuts action with those parameters filled in.
3. Enable earnings privacy or app lock. Verify a canceled authentication reveals no earnings or saved data. Unlock the app before selecting a job if Siri's job picker is unavailable.
4. Start a timer for a named job. A second start must preserve the running timer. End the timer, check the hours in the draft, and confirm no shift is saved until reviewed and saved. Ending with no active timer reports that state.
5. Ask for entry, history and the calendar with the app closed, then with it already open. Each request must navigate once. The timer-ending route must retain draft hours on launch.
6. Verify a confirmed Siri entry appears in History, widgets, and today's enabled CSV backup. Remove any intentionally created test entries through the app when finished.

Apple controls Siri's language recognition and Apple Intelligence availability. This integration registers the app's actions and data with App Intents; it does not claim arbitrary conversational requests or Apple-defined assistant schemas that do not match shift tracking.

References: [AppIntent](https://developer.apple.com/documentation/appintents/appintent), [AppEntity](https://developer.apple.com/documentation/appintents/appentity), [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy).
