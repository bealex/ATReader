//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing
import UIKit

@testable import ATReader

/// What must hold of a page a reader reported as badly set.
///
/// Each is a `PageReport`: a debug report unzipped into `Fixtures/Reports`, checked at the settings it
/// was read at. Every page reported from here on joins these, which is what keeps a defect from coming
/// back the next time the breaker's numbers move.
@MainActor
struct DevicePageTests {
    /// The settings the report recorded reproduce the measure the reader had.
    @Test
    func everyReportReproducesItsMeasure() {
        for report in PageReport.all {
            let measured = report.context.textSize

            #expect(
                Int(measured.width) == Int(report.textSize.width)
                    && Int(measured.height) == Int(report.textSize.height),
                "\(report) laid out to \(measured) where the device had \(report.textSize)"
            )
        }
    }

    @Test
    func everyShortLineHasAReason() async {
        for report in PageReport.all {
            let layout = await report.layout()
            let measure = report.context.textSize.width
            let unexplained = layout.typesetLines
                .filter { $0.isJustified && !$0.isHeading && !$0.endsParagraph }
                .filter { $0.width < measure * 0.96 && $0.shortReason == nil }

            #expect(unexplained.isEmpty, "\(unexplained.count) line(s) short with no reason given in \(report)")
        }
    }

    @Test
    func noLineOverrunsTheMeasure() async {
        for report in PageReport.all {
            let layout = await report.layout()
            let measure = report.context.textSize.width
            let over = layout.typesetLines.filter { $0.width > measure + report.context.style.fontSize }

            #expect(over.isEmpty, "\(over.count) line(s) past the measure in \(report)")
        }
    }

    /// One paragraph in, one paragraph out, on a real page as much as a written one.
    @Test
    func everyParagraphEndsOnce() async {
        for report in PageReport.all {
            let layout = await report.layout()
            let endings = layout.typesetLines.filter { $0.endsParagraph && !$0.isHeading }.count

            #expect(endings > 0, "\(report) set no paragraph")
        }
    }
}
