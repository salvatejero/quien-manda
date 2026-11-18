import SwiftUI
import XCTest
@testable import QuienManda

final class AccessibilityTests: XCTestCase {
    func testTextScaleCap() {
        XCTAssertEqual(TextScale.factor(1.94, cap: 1.3), 1.3)
        XCTAssertEqual(TextScale.factor(0.82, cap: 1.3), 0.82) // el tope no agranda el texto pequeño
        XCTAssertEqual(TextScale.factor(1.5), 1.5)
    }

    /// WCAG 2.1: el texto mudo (≥ 4,5:1) sobre el suelo y sobre la mancha verde del fondo, la peor, a su máxima opacidad.
    func testMutedTextContrast() {
        for (style, blobAlpha) in [(UIUserInterfaceStyle.light, 0.38), (.dark, 0.34)] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let ground = rgb(.ground, traits), muted = rgb(.muted, traits)
            let blob = rgb(.verde, traits).map { $0 * blobAlpha } .enumerated().map { $0.element + ground[$0.offset] * (1 - blobAlpha) }
            XCTAssertGreaterThanOrEqual(ratio(muted, ground), 4.5, "\(style)")
            XCTAssertGreaterThanOrEqual(ratio(muted, blob), 4.5, "\(style)")
        }
        XCTAssertEqual(ratio([1, 1, 1], [0, 0, 0]), 21, accuracy: 0.01)
    }

    private func rgb(_ color: Color, _ traits: UITraitCollection) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map(Double.init)
    }

    private func ratio(_ a: [Double], _ b: [Double]) -> Double {
        func lum(_ c: [Double]) -> Double {
            let l = c.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let (hi, lo) = (max(lum(a), lum(b)), min(lum(a), lum(b)))
        return (hi + 0.05) / (lo + 0.05)
    }
}
