# Release Checklist — TestFlight & App Store

Everything to decide, fix, and set up before the first TestFlight build, plus the
extra items needed for a public App Store release. Ordered roughly by "do this
first". Last reviewed: 2026-07-19.

## Path: TestFlight first

TestFlight is optional in principle (you can archive and submit straight to App
Store review), but there is no real trade-off: the **same uploaded build** serves
internal TestFlight, external TestFlight, and the App Store submission. Internal
TestFlight needs no review at all and is available minutes after the build
processes, so the plan is:

1. Internal TestFlight (just us) — shake out install/signing/server issues
2. External TestFlight (public link, one-time Beta App Review) — only if we want
   outside testers
3. App Store submission — same build or a later one, when ready

### Distribution end-state: two viable options

Precedent from the self-hosted-client world:

- **External TestFlight as the permanent channel.** This is what the
  first-party Audiobookshelf app does — it has never shipped to the App Store
  and lives in perpetual TestFlight beta via a public invite link. Constraints:
  10,000-tester hard cap, builds expire after 90 days (so periodic re-uploads),
  lighter one-time Beta App Review instead of full review, no demo server
  needed. For a personal/small-audience app this may be all we ever need.
- **Full App Store release.** What ShelfPlayer, Plappa, Jellyfin etc. do:
  listed as pure clients ("requires a self-hosted server"), with a working demo
  server URL + credentials in the App Review notes. Requires everything in
  section 5, including the reviewer-reachable demo instance below.

Decision: start with internal → external TestFlight; plan to stand up a
reviewer-reachable demo when we go for the App Store.

### Reviewer-reachable demo server (needed for App Store, planned)

The reviewer can't join our tailnet, so the demo instance must be publicly
reachable over HTTPS for the duration of the review:

- [ ] Preferred: **Tailscale Funnel** — temporarily exposes the existing server
      publicly over HTTPS on its `ts.net` name, no VPS needed. Enable for the
      review window, disable after approval.
- [ ] Alternative: small public demo instance (cheap VPS/container), like
      Audiobookshelf's `audiobooks.dev` (`demo`/`demo`).
- [ ] Seed a demo account with plausible training data (the reviewer must be
      able to log in and see the app working).
- [ ] Put the URL + credentials in the App Review notes on each submission.

---

## 1. Decisions to lock in (before the first upload)

- [ ] **Bundle ID** — currently `com.ardennl.OpenHealthSync`. This becomes
      permanent on first upload to App Store Connect; changing it later means a
      brand-new app record (losing testers/reviews). Decide the final
      `com.<something>.loopback` now. The domain doesn't need to exist —
      reverse-DNS is convention only. (Was waiting on the Loopback domain.)
- [ ] **App name "Loopback"** — claimed in App Store Connect when the app record
      is created. Create the record early to reserve the name.
- [x] **iPhone-only or iPad too?** — Decided 2026-07-19: iPhone-only for v1.
      `TARGETED_DEVICE_FAMILY = 1` set; iPad orientation settings removed.
- [x] **Deployment target** — Done 2026-07-19: lowered to iOS 26.0; builds
      clean, nothing needed 26.2.
- [x] **Paid Apple Developer Program** — Confirmed 2026-07-19: paid enrollment
      in place.

## 2. Code & config fixes (before the first upload)

- [x] **Remove embedded API credentials.** Done 2026-07-19: dropped the plist
      fallback in `SessionStore.resolveCredentials()`, the plist read in
      `WorkoutAPIClient.init`, and the `WorkoutAPIKey` / `WorkoutAPIBaseURL`
      keys from `Info.plist`. The whole `Secrets.xcconfig` mechanism was
      removed with it (pbxproj base-configuration references,
      `Secrets.example.xcconfig`, README setup steps) — the server URL is
      user-entered at login. The local gitignored `Secrets.xcconfig` still sits
      on disk (unused, key already revoked); delete at will.
- [x] **Resolve duplicate HealthKit purpose string.** Done 2026-07-19: deleted
      the `Info.plist` copy; the build-settings
      `INFOPLIST_KEY_NSHealthShareUsageDescription` ("Loopback reads your
      workouts, sleep and recovery…") is the single source. Verified in the
      built app's merged Info.plist.
- [x] **HTTP server access (decided: keep HTTP, no public HTTPS).** Done
      2026-07-19: added `NSAppTransportSecurity` →
      `NSAllowsArbitraryLoads = true` and `NSLocalNetworkUsageDescription` to
      `Info.plist`. At review time, justification: "connects to a private,
      self-hosted server whose address the user configures" — standard for
      Audiobookshelf/Jellyfin-style apps. Optional later: `tailscale cert`
      gives free HTTPS on the `ts.net` name if we ever want to drop the ATS
      exception.
- [x] **Export compliance shortcut.** Done 2026-07-19: added
      `ITSAppUsesNonExemptEncryption = NO` to Info.plist.
- [x] **http/https scheme dropdown for server entry.** Done 2026-07-19: login
      and settings now use `ServerURLInput` (scheme picker + host field, the
      Plappa/Audiobookshelf-client pattern), so HTTP-only servers work without
      typing `http://` by hand. Pasting a full URL moves its scheme into the
      dropdown.
- [x] **Remove the personal default server URL.** Done 2026-07-19:
      `LoginView.defaultServerURL` (a personal tailnet hostname) is now
      `#if DEBUG`-only; Release builds prefill nothing.
- [ ] **Build numbering.** `CURRENT_PROJECT_VERSION` (build number) must
      increase with every upload; `MARKETING_VERSION` (1.0) can stay per
      release.

Already in good shape (verified 2026-07-19): 1024×1024 app icon with no alpha,
HealthKit + background-delivery entitlements, automatic signing with team set,
launch screen and orientations configured, `Secrets.xcconfig` gitignored.

## 3. First TestFlight (internal)

- [ ] Create the app record in App Store Connect: name **Loopback**, final
      bundle ID, primary language, SKU (any internal string, e.g. `loopback-001`).
- [ ] Xcode: Product → Archive → Distribute App → App Store Connect. Automatic
      signing creates the distribution cert/profile, including the HealthKit
      background-delivery capability.
- [ ] Wait for processing (usually minutes), add ourselves as internal testers
      (App Store Connect users, up to 100), install via the TestFlight app.
- [ ] Smoke-test on a real device: login against the server over
      Tailscale/LAN, HealthKit read permissions, background delivery.

## 4. External TestFlight (only if we want outside testers)

- [ ] One-time **Beta App Review** (lighter than full review, but checks
      HealthKit basics).
- [ ] Beta description + feedback email in App Store Connect.
- [ ] Demo account on the server for the reviewer (login is required to use the
      app).
- [ ] Public link or email invites; up to 10,000 testers, builds expire after
      90 days.

## 5. App Store release (beyond TestFlight)

HealthKit apps get extra scrutiny. On top of the standard listing assets
(screenshots for required device sizes, description, keywords, support URL):

- [ ] **Privacy policy URL — mandatory for HealthKit apps.** Most common
      HealthKit rejection. Must state which health data we read and that it
      syncs to the user's server for coaching. Never used for advertising.
- [ ] **App Privacy questionnaire** in App Store Connect: declare
      Health & Fitness data as collected and linked to identity.
- [ ] **Account deletion in-app** — guideline 5.1.1(v): apps with login must
      let users delete their account from within the app. Natural home: the
      deferred devices/token-management screen. Hard requirement for release,
      not for TestFlight.
- [ ] **Reviewer demo account** in the review notes — see "Reviewer-reachable
      demo server" above (Tailscale Funnel or public demo instance).
- [ ] Full **App Review** pass (first submission typically 1–3 days).

## Open questions

- Final bundle ID / Loopback domain
