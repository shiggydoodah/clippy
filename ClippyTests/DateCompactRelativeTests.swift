import Foundation
import Testing
@testable import Clippy

/// The hand-rolled compact age string used in list rows. Values sit
/// mid-bucket so the wall-clock drift between constructing the date and
/// formatting it cannot flip a boundary.
struct DateCompactRelativeTests {

    @Test func immediatePastReadsNow() {
        #expect(Date(timeIntervalSinceNow: -3).compactRelativeDisplay == "now")
    }

    @Test func futureDatesClampToNow() {
        // A clock adjustment can put lastUsedAt in the future — never show
        // a negative age.
        #expect(Date(timeIntervalSinceNow: 120).compactRelativeDisplay == "now")
    }

    @Test func secondsMinutesHoursAndDays() {
        #expect(Date(timeIntervalSinceNow: -45).compactRelativeDisplay == "45s")
        #expect(Date(timeIntervalSinceNow: -300).compactRelativeDisplay == "5m")
        #expect(Date(timeIntervalSinceNow: -7_200).compactRelativeDisplay == "2h")
        #expect(Date(timeIntervalSinceNow: -259_200).compactRelativeDisplay == "3d")
    }
}
