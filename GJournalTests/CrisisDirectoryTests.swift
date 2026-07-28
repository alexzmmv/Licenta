import XCTest
import SwiftUI
@testable import GJournal

/// The crisis screen previously handed US-only numbers (988, 741741) to every
/// user worldwide. These lock in the rule that we never show a number that
/// doesn't connect in the user's region.
final class CrisisDirectoryTests: XCTestCase {

    func testUnknownRegionNeverShowsARegionSpecificNumber() {
        for region in ["DE", "RO", "JP", "BR", "IN", "ZA", nil] {
            let resources = CrisisDirectory.resources(for: region)
            XCTAssertFalse(resources.isEmpty, "every region must get something")

            let schemes = resources.compactMap(\.url?.scheme)
            XCTAssertFalse(
                schemes.contains("tel") || schemes.contains("sms"),
                "region \(region ?? "nil") must not be given a phone number we can't verify"
            )
        }
    }

    func testEveryRegionCanReachAnInternationalDirectory() {
        for region in ["US", "CA", "GB", "IE", "AU", "DE", "RO", nil] {
            let resources = CrisisDirectory.resources(for: region)
            let hasDirectory = resources.contains { ($0.url?.scheme ?? "").hasPrefix("http") }
            XCTAssertTrue(hasDirectory, "region \(region ?? "nil") must have a web directory fallback")
        }
    }

    func testUSGetsTheNationalLifeline() {
        let urls = CrisisDirectory.resources(for: "US").compactMap(\.url?.absoluteString)
        XCTAssertTrue(urls.contains("tel:988"))
    }

    func testUKAndIrelandGetSamaritans() {
        for region in ["GB", "IE"] {
            let urls = CrisisDirectory.resources(for: region).compactMap(\.url?.absoluteString)
            XCTAssertTrue(urls.contains("tel:116123"), "\(region) should reach Samaritans")
        }
    }

    func testEveryResourceHasANonEmptySpokenLabel() {
        for region in ["US", "CA", "GB", "AU", "DE", nil] {
            for resource in CrisisDirectory.resources(for: region) {
                XCTAssertFalse(resource.title.isEmpty)
                XCTAssertFalse(resource.subtitle.isEmpty)
                XCTAssertTrue(
                    resource.spokenLabel.contains(resource.title),
                    "VoiceOver must announce the resource name"
                )
            }
        }
    }

    func testEveryResourceHasAUsableURL() {
        for region in ["US", "CA", "GB", "IE", "AU", "DE", nil] {
            for resource in CrisisDirectory.resources(for: region) {
                XCTAssertNotNil(resource.url, "\(resource.title) must be actionable, not decorative")
            }
        }
    }
}
