# Staff Hub Build 2 — App Store Connect draft

## Beta description

Staff Hub gives practice employees and office managers a secure mobile view of schedules, paid time off, attendance, and in-app updates. Build 2 introduces a responsive role-specific schedule, improved keyboard handling on sign-in, persistent authenticated sessions, and a dedicated synthetic Test Practice for Apple review.

## What to Test

Please test both supplied roles in the Test Practice:

1. Sign in as the Office Manager and review the team schedule. In portrait, choose dates from the date strip and review daily staffing. Rotate the device or use a wide iPad window to view the Sunday–Saturday team week. Open an unlocked future shift to edit it; past shifts and shifts with timesheet activity remain read-only.
2. Review the pending PTO queue, balances, attendance history, blackout period, and in-app notifications.
3. Sign out, then sign in as the Employee. Confirm that only that employee’s published schedule, PTO data, and notifications are visible. Portrait uses an upcoming-shift agenda; landscape/wide layouts use a personal weekly grid.
4. Force-quit and reopen the app. The authenticated session should be restored. Explicit Sign Out should return to the neutral Staff Hub login screen.

All Test Practice content is synthetic and resets nightly. Email, push delivery, and Google Calendar delivery are disabled for this practice; in-app notifications remain available.

## Sign-in information fields

### Primary — Office Manager

- Username: `appreview.manager@secondsighttechnologies.com`
- Password: `[PASTE FROM APPROVED PASSWORD-MANAGER RECORD]`

### Secondary — Employee

- Username: `appreview.employee@secondsighttechnologies.com`
- Password: `[PASTE FROM APPROVED PASSWORD-MANAGER RECORD]`

Never place either password in source control, build notes, logs, or chat history. App Store Connect is the only review-facing destination for these credential values.

## Reviewer walkthrough notes

- The application opens on the sign-in screen. Use the Office Manager credential first.
- Select **Schedule** in the tab bar. The default date is today and weeks run Sunday through Saturday.
- Rotate to landscape to see the full team week. Subtle **Draft**, **Modified**, and warning treatments demonstrate schedule exceptions.
- Select an unlocked future shift to view manager editing. Locked historical/timesheet-linked shifts open read-only details.
- Select **Time Off** to review synthetic balances, an approved request, and pending requests.
- Select **Inbox** to review synthetic in-app notifications.
- Sign out from the account menu and repeat with the Employee credential. Employee access is intentionally limited to that employee’s records and published shifts.
- Test Practice is isolated from live practice data. No reviewer account has Owner/Admin access.

## Secure account provisioning after deployment approval

1. Deploy the reviewed migration only after explicit production approval.
2. Sign in to Staff Hub as an existing real Owner/Admin and switch to **Test Practice · Apple Review**.
3. Open **Team** and select **Create access link** for Alex Morgan and Jordan Lee.
4. Open each one-time link privately, generate a unique password of at least 20 characters in the organization password manager, and complete account setup.
5. Verify each credential in the production iOS app, then save it in the restricted App Store Review password-manager record.
6. Paste the values into App Store Connect’s Sign-in Information fields once. Do not distribute them to staff.

## External staff installation and login checklist

- Install TestFlight from the App Store.
- Open the staff member’s TestFlight invitation and install Staff Hub Build 2.
- Launch Staff Hub and enter the staff member’s existing Staff Hub email and password.
- Confirm the practice name shown after sign-in is correct.
- Allow notifications if desired; notification permission can be changed later in iOS Settings.
- Open Schedule and confirm today’s view. Rotate once to discover the weekly layout.
- Force-quit and relaunch once to confirm the session restores.
- Use the account menu’s Sign Out action on shared devices.

## Release controls

- Marketing version: `1.0.0`
- Build: `2`
- Archive: local validation only
- Upload: intentionally not performed
- Production Supabase migration: requires explicit approval immediately before deployment
