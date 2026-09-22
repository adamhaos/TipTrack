# Share card verification

The iOS Simulator Debug build passed with the updated sharing sheet.

Rendered the production card at 2× export resolution using a macOS SwiftUI harness (only the platform image adapter differs):

- All selectable shift details, workplace, date, total and download QR.
- Privacy defaults: hours and QR only.
- Minimal card with every detail and QR disabled.
- Long workplace name and large total.

Visually inspected the layouts. Apple Vision decoded every enabled QR to https://apps.apple.com/us/app/tiptrack3r/id6809030435.

These sample images contain illustrative data. The native iPhone activity sheet has not been exercised on a physical device.
