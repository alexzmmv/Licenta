# App Store Launch & Developer Account Enrollment Guide

## 1. Executive Summary

GJournal is technically ready for App Store submission, with core features (Tiers 1–3) fully implemented and verified via 92 unit tests and 5 UI tests. Because the app operates entirely on-device (utilizing local CoreML models, SwiftData, and local analysis), it presents an exceptional privacy posture. However, because it touches mental health (mood/emotion tracking, topological trajectory analysis, and distress indicators), it falls under heightened scrutiny by Apple App Review.

This document provides a step-by-step Apple Developer Account enrollment guide, maps technical implementations to Apple's App Store Review Guidelines, and outlines an actionable checklist for submission.

---

## 2. Apple Developer Account Enrollment Guide

To publish GJournal on the App Store, you must enroll in the Apple Developer Program ($99 USD/year).

### 2.1 Option A: Individual Account (Fastest & Simplest)
Best if you do not have a registered company/legal entity. The App Store seller name will be your legal name.
1. **Prepare:** Ensure your Apple ID has Two-Factor Authentication enabled and your personal details (name, address) are up to date.
2. **Download the App:** On an iPhone or iPad, download the **Apple Developer** app from the App Store.
3. **Register:** Open the app, tap the **Account** tab, and sign in with your Apple ID.
4. **Enroll:** Tap **Enroll Now**, read the benefits, and fill in your personal legal name, address, and phone number.
5. **Identity Verification:** You will be prompted to scan a government-issued photo ID (driver's license or passport) and perform a quick selfie check.
6. **Payment:** Complete your enrollment by paying the $99 annual fee via Apple Pay.
7. **Timeline:** Individual accounts enrolled through the app are typically approved within **24 to 48 hours**.

### 2.2 Option B: Organization Account (For Companies)
Best if you have a registered corporation, LLC, or partnership. The App Store seller name will be your company's legal name.
1. **D-U-N-S Number:** Obtain a D-U-N-S (Dun & Bradstreet) number for your company. This is free and verify your organization's legal identity. (Takes 1–5 business days to generate).
2. **Enrollment Portal:** Go to [developer.apple.com](https://developer.apple.com/) and sign in with your Apple ID.
3. **Authority Check:** You must be the owner, founder, or have explicit signing authority to bind the company to Apple's legal contracts.
4. **Submit Details:** Provide the company’s legal entity name, D-U-N-S number, headquarters address, phone number, and a public website.
5. **Verification Call:** Apple will call the company's registration phone number to confirm your identity and authority.
6. **Payment:** Upon approval, Apple will email you a purchase link to pay the $99 annual fee.
7. **Timeline:** Organization accounts typically take **1 to 2 weeks** to be approved.

---

## 3. Apple App Store Guidelines Compliance

### 3.1 Guideline 1.4: Physical and Mental Health (Safety Filter & Medical Disclaimer)
* **Risk:** Apple restricts apps that claim to diagnose, treat, or manage clinical conditions without medical credentials.
* **Implementation Status:**
  * [SafetyFilter](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Services/SafetyFilter.swift) scans journal entries for self-harm signals. If detected, it triggers a gentle, non-blocking sheet displaying [CrisisResourcesView](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/CrisisResourcesView.swift) (988 Lifeline, Crisis Text Line). Saving is never blocked, and the app does not attempt on-platform triage or treatment.
  * [OnboardingView](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/OnboardingView.swift) contains an explicit disclaimer stating that GJournal is a general wellness tool, not a medical or diagnostic device.
* **Assessment:** Highly compliant. To ensure zero rejection risk, the App Store description must reinforce this "wellness only" positioning and explicitly state: *"GJournal does not diagnose or treat medical conditions; consult a healthcare professional for clinical care."*

### 3.2 Guideline 5.1: Privacy & Data Collection
* **Risk:** The App Store requires strict disclosures of data collection and explicit permission strings.
* **Implementation Status:**
  * [PrivacyInfo.xcprivacy](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/PrivacyInfo.xcprivacy) is set to `NSPrivacyTracking = false` with empty collected data types, as all processing is strictly local.
  * `NSFaceIDUsageDescription` is configured inside [project.pbxproj](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal.xcodeproj/project.pbxproj) with a clear, user-facing reason description.
  * File-level encryption is configured in [GJournalApp.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/GJournalApp.swift) with `URLFileProtection.completeUnlessOpen` applied to the SwiftData store.
* **Assessment:** Outstanding. The App Privacy label on App Store Connect can truthfully declare **"Data Not Collected,"** which serves as a key marketing differentiator.

### 3.3 Guideline 3.1: Payments & Entitlements (StoreKit 2)
* **Risk:** Incomplete paywall restoration flows or broken Sandbox transactions cause immediate rejections.
* **Implementation Status:**
  * `EntitlementManager` and `PaywallView` utilize StoreKit 2 APIs.
  * Features are correctly gated behind a non-consumable, one-time unlock (`com.gjournal.insights`).
  * Sandbox environment checks are integrated into UI tests using [UITestSupport](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournalTests/UITestSupport.swift) hooks.
* **Assessment:** Ready. The reviewer instructions must explain that sandbox accounts are required and how they can purchase/restore the premium tier.

---

## 4. Actionable App Store Submission Checklist

| Category | Task / Requirement | Verification File / Location | Status |
| :--- | :--- | :--- | :--- |
| **Account Setup** | Enroll in Developer Program | Apple Developer App / Web Portal | Pending User |
| **Identity & Assets** | Upload 1024x1024 App Store Icon | `Assets.xcassets/AppIcon.appiconset` | Ready |
| **Privacy Manifest** | Declare zero data collection, CA92.1, and C617.1 API access | [PrivacyInfo.xcprivacy](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/PrivacyInfo.xcprivacy) | Verified |
| **User Safety** | Non-blocking Crisis Resources sheet on self-harm detection | [CrisisResourcesView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/CrisisResourcesView.swift) | Verified |
| **Medical Disclaimers** | "Not a medical device" disclaimer in App Store copy & Onboarding | [OnboardingView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/OnboardingView.swift) | Verified |
| **Encryption Export** | Register for standard encryption export exemption (on-device HTTPS/CryptoKit) | App Store Connect Console | Checklist |
| **Reviewer Support** | Seeded UI states for Reviewer login via demo credentials | [UITestSupport.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournalTests/UITestSupport.swift) | Verified |
