# Staff Hub for iOS

Native SwiftUI access to the existing Staff Hub backend for Griffin Eye Care, Senoia Eye Care, and Maxara. The iOS 18 app is optimized for iPhone and uses adaptive SwiftUI layouts on iPad. Stable internal source and database identifiers retain the original `PTOHub`/`pto-hub` names for compatibility.

## Included in v1

- Password sign-in with Supabase Auth session restoration
- Employee PTO balance, published schedule, request history, validated request creation, and future cancellation
- Manager live attendance (read-only), schedule creation/editing, and PTO approvals
- Owner/Admin business switching
- Inbox read state and push routing for request and schedule events
- Protected per-user/per-business snapshots for read-only offline launch
- No clock controls, location access, timesheet editing, reports, or team administration

## Local setup

1. Install Xcode 26+ and XcodeGen.
2. Copy the matching `Config/Local-*.xcconfig.example` files to their non-example names.
3. Add the correct environment's Supabase project URL and publishable key. Debug and Staging must use staging; Release uses production. Never add a secret or service-role key.
4. Generate the project and open it:

```bash
xcodegen generate --spec project.yml
open PTOHub.xcodeproj
```

The Supabase Swift package is pinned to `2.46.0`. Authentication credentials are persisted by the SDK; cached snapshots are written with iOS Data Protection under Application Support and separated by Auth user and business UUID.

### Simulator demo

Debug builds running in the iOS Simulator show Employee, Manager, and Owner demo buttons below Sign In. These sessions use in-memory sample PTO, schedule, attendance, request, and notification data. Demo mutations stay local, push registration is disabled, and the demo implementation is excluded from device and Release builds at compile time.

## Configuration and release inputs

`Debug`, `Staging`, and `Release` use separate ignored client configurations. The release identity is `com.secondsighttechnologies.staffhub` under Apple signing team `28V3NG52GP`. Before TestFlight, complete:

- APNs key (`.p8`), Apple team ID, and key ID to the server environment
- Production Supabase URL and publishable key in the release configuration
- Associated App Store Connect app and unlisted-distribution approval

APNs credentials and the Supabase service-role key belong only in Supabase Edge Function secrets. The app entitlement selects development APNs for Debug/Staging and production APNs for Release.

## Verification

```bash
xcodegen generate --spec project.yml
xcodebuild -project PTOHub.xcodeproj -scheme PTOHub \
  -destination 'generic/platform=iOS Simulator' build
```

Run unit and UI tests from the `PTOHub` scheme on an installed simulator. Backend migration, pgTAP, and web verification live in the sibling `pto` project.

## Pilot sequence

Start with Griffin Eye Care in TestFlight. Compare published schedules, PTO balances/requests, and foreground attendance updates with the web app. After parity is confirmed, enable Senoia Eye Care and Maxara, validate production APNs, and then request unlisted App Store distribution.
