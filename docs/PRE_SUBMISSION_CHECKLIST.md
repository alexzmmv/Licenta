# GJournal — Pre-Submission Checklist

Everything below needs a human decision or a real-world value that code can't
invent. The production-readiness work left deliberate placeholders rather than
guessing; each one is listed with where it lives and what happens if it ships
unchanged.

Status legend: 🔴 blocks submission · 🟠 likely rejection · 🟡 decide before v1.0

---

## 🔴 Blockers — the build will be rejected or broken without these

### 1. Privacy Policy URL
- **Where:** `GJournal/Utilities/AppLinks.swift:18`
- **Now:** `https://example.com/gjournal/privacy`
- **Needed:** a real, publicly reachable page you host. The *same* URL also goes
  into App Store Connect → App Privacy. Reviewers follow it.
- **If unchanged:** Guideline 5.1.1 rejection. It's linked from both the paywall
  and Settings → About, so a reviewer will hit it.

### 2. Support contact
- **Where:** `GJournal/Utilities/AppLinks.swift:21`
- **Now:** `mailto:support@example.com`
- **Needed:** a mailbox you actually read.
- **If unchanged:** Settings → Contact Support opens a dead compose window.

> A DEBUG-only warning row now appears at the bottom of Settings while either of
> these still contains `example.com` (`AppLinks.hasUnconfiguredLinks`).

### 3. Bundle identifier
- **Where:** `GJournal.xcodeproj/project.pbxproj:540`
- **Now:** `GJ.GJournal`
- **Needed:** reverse-DNS on a domain you control, e.g. `com.gjournal.app`.
- **If unchanged:** the ID is **permanent** once registered in App Store Connect
  and can never be changed for that app record. This must be fixed *before the
  first upload*, not before release.
- Note the StoreKit product ID already uses the right convention
  (`com.gjournal.insights`, `EntitlementManager.swift:7`) — the bundle ID is the
  odd one out.

### 4. App Store Connect IAP product
- **Where:** `GJournal/GJournal.storekit` is a **local test file only** — it is
  now excluded from the shipping bundle and wired into the scheme's Run action.
- **Needed:** create a real non-consumable `com.gjournal.insights` in App Store
  Connect, priced, with Family Sharing enabled (the paywall advertises it), and
  submit it *with* the build.
- **If unchanged:** `loadProducts()` returns nothing in production. The paywall
  degrades honestly ("Store Unavailable" + Try Again), but nobody can buy.

---

## 🟠 Likely rejection

### 5. iPad support
- **Where:** `project.pbxproj:311` → `TARGETED_DEVICE_FAMILY = "1,2"`, alongside
  `UIRequiresFullScreen = YES` and portrait-only.
- **Decision needed:** either run every screen on an iPad and fix the layouts,
  or set the value to `"1"` (iPhone only).
- **If unchanged:** the app ships claiming iPad support. Apple tests on iPad and
  rejects stretched or broken layouts. Setting `"1"` is the cheap, safe answer
  for v1.0 — iPad can be added later without penalty.

### 6. Screenshots, description, and age rating
- Not code, but required. Note the app surfaces **crisis / self-harm resources**
  (`CrisisResourcesView`, triggered by `SafetyFilter`). Declare this honestly in
  the age-rating questionnaire; a mismatch found in review is a slow rejection.

---

## 🟡 Decide before v1.0

### 7. Deployment target
- **Where:** `project.pbxproj:301` → `IPHONEOS_DEPLOYMENT_TARGET = 18.0`
- SwiftData shipped in iOS 17, and no API in this codebase was identified as
  needing 18.0. Staying at 18.0 excludes the iPhone XR / XS generation.
- **Action:** try lowering to 17.0. If it compiles and the suite passes, take the
  extra devices. If something genuinely requires 18.0, leave it and note why.

### 8. Version and build numbers
- **Where:** `project.pbxproj:302,298` → `MARKETING_VERSION = 1.0`,
  `CURRENT_PROJECT_VERSION = 1`
- Fine for a first upload. Remember the build number must increase on **every**
  upload, even for rejected builds.

### 9. Crisis phone numbers
- **Where:** `GJournal/Views/CrisisResourcesView.swift` (`CrisisDirectory`)
- Hardcoded lines are limited to ones verified with confidence: US 988 / 741741,
  CA 988, GB+IE Samaritans 116 123 and Shout 85258, AU Lifeline 13 11 14. Every
  other region gets **web directories only**, never a phone number — enforced by
  `CrisisDirectoryTests.testUnknownRegionNeverShowsARegionSpecificNumber`.
- **Action:** re-verify these five before each release. A crisis line that has
  been renumbered is the worst possible bug in this app. Adding a region means
  adding it to `CrisisDirectory.resources(for:)`; the test will hold the line on
  everything else.

### 10. Physical-device pass
- Not yet done. Three things only a real device proves:
  - **Face ID / Touch ID** — the simulator has no enrolled biometrics, so the
    entire biometric branch (including "Forgot PIN?" recovery) is untested on
    hardware. Only the destructive branch is covered by UI tests.
  - **PBKDF2 timing** — 350k iterations run synchronously on the main thread
    (`AuthManager.swift`). If PIN entry visibly hangs on an older device, move it
    off-main with a spinner.
  - **MetricKit** — crash diagnostics never fire in the simulator.

---

## Verified — no action needed

These were flagged during the audit and checked against the source; each is fine:

- `NSFaceIDUsageDescription` is set at the **project** level
  (`project.pbxproj:436,498`, owned by the `PBXProject` config list) and is
  inherited by the app target. This was reported as a possible launch-day crash.
  It isn't.
- `ITSAppUsesNonExemptEncryption = NO` is already set, so uploads won't stall on
  the export-compliance question.
- `PrivacyInfo.xcprivacy` lands at the bundle root (confirmed in a built `.app`).
- `GJournal.storekit` no longer ships as a bundle resource.
- `seed_data.json` **does** still ship. This is deliberate: DEBUG UI tests depend
  on it, and `membershipExceptions` removes a file from *all* configurations, not
  just Release. It contains no user data.

---

## Known limitations shipping in v1.0 (intentional)

- **No iCloud sync.** Backup is JSON export/import via the share sheet
  (Settings → Export All Data / Import from Backup). This is what keeps the
  "never leaves your device" claim true.
- **English only.** The app runs fine in en, but notification copy, crisis copy,
  and every `errorMessage` are raw `String`s invisible to the localisation
  extractor. A second locale needs those signatures converted to
  `LocalizedStringKey` first.
- **Dynamic Type is partial.** The reading path (entry titles, bodies, prompts,
  settings) uses semantic styles and scales. The dashboard week strip and
  calendar grid use `@ScaledMetric` so type and tile grow together, with the
  calendar capped since a 7-column grid can't widen. Remaining fixed sizes are
  decorative glyphs and large emoji, which shouldn't scale.
- **Entries are editable on the day they're written only.** Enforced in
  `LocalJournalRepository.updateBit`, not just hidden in the UI.
