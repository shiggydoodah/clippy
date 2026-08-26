import SwiftUI
import Testing
@testable import Clippy

/// Color(hexString:) must accept exactly the forms ItemClassifier calls a
/// `colour` item — the preview swatch and classification must never disagree.
struct ColorHexTests {

    @Test func shorthandRGBExpandsEachDigit() {
        #expect(Color(hexString: "#abc") == Color(
            .sRGB, red: 0xAA / 255, green: 0xBB / 255, blue: 0xCC / 255, opacity: 1
        ))
    }

    @Test func sixDigitFormParsesChannels() {
        #expect(Color(hexString: "#336699") == Color(
            .sRGB, red: 0x33 / 255, green: 0x66 / 255, blue: 0x99 / 255, opacity: 1
        ))
    }

    @Test func eightDigitFormCarriesAlpha() {
        #expect(Color(hexString: "#33669980") == Color(
            .sRGB, red: 0x33 / 255, green: 0x66 / 255, blue: 0x99 / 255, opacity: 0x80 / 255
        ))
    }

    @Test func caseAndSurroundingWhitespaceAreAccepted() {
        #expect(Color(hexString: " #FFF \n") == Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1))
    }

    @Test func invalidFormsReturnNil() {
        #expect(Color(hexString: "fff") == nil)      // missing #
        #expect(Color(hexString: "#ggg") == nil)     // not hex
        #expect(Color(hexString: "#abcd") == nil)    // 4 digits — no #RGBA form
        #expect(Color(hexString: "#abcde") == nil)   // 5 digits
        #expect(Color(hexString: "#") == nil)
        #expect(Color(hexString: "") == nil)
    }
}
