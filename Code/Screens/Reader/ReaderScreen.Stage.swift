//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import DesignSystem
import SwiftUI

extension ReaderScreen {
    /// What the page and the controls standing over it both read: how the window is divided, whether
    /// the controls are up, and whatever stands over the page.
    @Observable @MainActor
    final class Stage {
        let settings: ReaderSettings

        /// The window's size, which is what the page is set against whatever chrome is on screen.
        var sheetSize: CGSize = .zero

        /// The device's own bands as a page takes them, leaving out the column a vertical bar stands in.
        var safeArea = EdgeInsets()

        /// Where the system stands its own bar, and so where the controls stand.
        var band: DeviceBand = .top

        /// A page fills the screen, and the controls are a tap in the middle away.
        var isChromeHidden = true

        /// True while the way back is on its way out.
        var fading = false

        /// The note a marker was tapped for, with where that marker stands.
        var note: Model.TappedNote?

        /// A table opened whole from its picture on the page.
        var table: Model.ShownTable?

        /// Text picked off the page, once the finger has come up and there is something to offer.
        var picked: Model.PickedText?

        var lookedUp: LookedUpTerm?
        var isSearching = false
        var query = ""
        var isShowingSettings = false
        var isShowingContents = false
        /// True while the marks standing on the page are listed, which only several of them do.
        var isShowingBookmarks = false
        var isTranslating = false
        var translating = ""

        #if DEBUG
            var report: SharedFile?
        #endif

        /// Where the controls take touches, in the window's space; everywhere else belongs to the page.
        @ObservationIgnored
        var touchAreas: [String: CGRect] = [:]

        init(settings: ReaderSettings) {
            self.settings = settings
        }

        /// True while something of the reader's own stands over the page, so a finger held on it does
        /// not go on choosing words underneath.
        var isPageCovered: Bool {
            #if DEBUG
                if report != nil { return true }
            #endif

            return isShowingContents || isShowingBookmarks || isShowingSettings || lookedUp != nil || isTranslating
                || table != nil
        }

        /// True while an aside covers the page, which then takes every touch to put it away.
        var hasAside: Bool { note != nil || picked != nil }

        /// How the sheet is divided: one page, or two with the binding between them.
        var spread: PageSpread {
            PageSpread(
                sheet: sheetSize,
                safeArea: safeArea,
                margins: settings.settledMargins,
                textSize: settings.fontSize
            )
        }

        /// Everything pagination depends on. A change to any of it re-lays the chapter.
        var layoutContext: ChapterLayout.Context {
            let spread = spread

            return ChapterLayout.Context(
                style: settings.textStyle,
                margins: settings.settledMargins,
                pageSize: spread.pageSize,
                safeArea: spread.pageSafeArea
            )
        }

        /// The type size of the running head, which the layout's head band is read off as well.
        var runningHeadSize: CGFloat { settings.fontSize * ChapterLayout.Context.runningHeadScale }

        /// Whether the status bar goes away with the controls: only where that moves nothing, under a
        /// notch or in a vertical bar the page makes no room for.
        var hidesStatusBar: Bool {
            isChromeHidden && (safeArea.top >= Self.deviceBandDepth || band.isDownASide)
        }

        /// Deeper than any status bar, shallower than any notch.
        private static let deviceBandDepth: CGFloat = 40

        /// How long the controls take to fade in or out.
        static let chromeFade: Double = 0.25
    }
}
