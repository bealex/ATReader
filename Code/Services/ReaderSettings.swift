//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import SwiftUI
import UIKit

/// One screen as reading sees it: this kind of device, at this window size.
///
/// Folded and unfolded, upright and on its side, and each width a window is split to are screens of their
/// own, since type that reads well on one is too big or too small on another.
struct ReadingScreen: Hashable, Sendable {
    let id: String

    init(windowSize: CGSize) {
        id = "\(Self.model) \(Int(windowSize.width.rounded()))x\(Int(windowSize.height.rounded()))"
    }

    /// A window not yet on a screen has no size to be told apart by.
    var isKnown: Bool { !id.hasSuffix(" 0x0") }

    /// The device's model, `iPhone19,4`: a library restored onto another device starts from its own.
    private static let model: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }

        var system = utsname()

        uname(&system)

        return withUnsafeBytes(of: &system.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "device"
        }
    }()
}

/// Typography, margins and page tint for the reader, persisted across launches.
///
/// How the text is set is kept for each screen apart; the colours and what a tap does are kept once.
@Observable @MainActor
final class ReaderSettings {
    /// A page's two colours. What the reader chooses is one of these for the light hours and one for
    /// the dark, or a single one for both.
    enum Theme: String, CaseIterable, Identifiable {
        case paper
        case sepia
        case night
        case green

        var id: String { rawValue }

        var title: String {
            switch self {
                case .paper: String(localized: "Paper")
                case .sepia: String(localized: "Sepia")
                case .night: String(localized: "Night")
                case .green: String(localized: "Green")
            }
        }

        var background: Color {
            switch self {
                case .paper: Color(red: 0.99, green: 0.99, blue: 0.97)
                case .sepia: Color(red: 0.96, green: 0.91, blue: 0.82)
                case .night: Color(red: 0.09, green: 0.09, blue: 0.11)
                case .green: Color(red: 0.02, green: 0.02, blue: 0.02)
            }
        }

        var foreground: Color {
            switch self {
                case .paper: Color(red: 0.11, green: 0.11, blue: 0.12)
                case .sepia: Color(red: 0.25, green: 0.19, blue: 0.11)
                case .night: Color(red: 0.85, green: 0.85, blue: 0.88)
                case .green: Color(red: 0.29, green: 0.63, blue: 0.35)
            }
        }

        /// True for a page meant to be read in the dark, which is what the system asks for by name.
        var isDark: Bool { self == .night || self == .green }

        /// Holds the status bar and the controls to the page rather than to the system.
        var colorScheme: ColorScheme { isDark ? .dark : .light }
    }

    /// What a face and a weight are belongs to the typesetter; what the reader picked belongs here.
    public typealias Face = BookFace
    public typealias Weight = BookWeight

    /// Left-aligned keeps an even word spacing; justified keeps an even right edge.
    enum Alignment: String, CaseIterable, Identifiable, Codable {
        case justified
        case leading

        var id: String { rawValue }

        var title: String {
            switch self {
                case .justified: String(localized: "Justified")
                case .leading: String(localized: "Left-aligned")
            }
        }

        var systemImage: String {
            switch self {
                case .justified: "text.justify"
                case .leading: "text.alignleft"
            }
        }
    }

    static let fontSizeRange: ClosedRange<Double> = 14 ... 30
    static let lineSpacingRange: ClosedRange<Double> = 0 ... 16
    static let marginRange: ClosedRange<Double> = 0 ... 100
    /// Tracking in points. A little either way is all a text face can take before it stops reading well.
    static let letterSpacingRange: ClosedRange<Double> = -0.5 ... 2

    /// How the text is set on one screen.
    struct Typesetting: Codable, Equatable {
        var fontSize: Double
        var lineSpacing: Double
        /// Space added between letters, in points.
        var letterSpacing: Double
        /// Page inset in points, applied on every edge.
        var margins: Double
        var face: Face
        var weight: Weight
        /// Russian sets well justified: its hyphenation dictionary is good and its words are long enough
        /// to fill a line. English justified in a narrow column pulls the words apart instead.
        var russianAlignment: Alignment
        /// Used for every language that isn't Russian.
        var englishAlignment: Alignment
        /// Words may be broken at the end of a line. A justified column reads far better for it: the
        /// only other way to reach the measure is to pull the words apart.
        var hyphenates: Bool
    }

    /// Each screen's typesetting, by ``ReadingScreen/id``.
    private var typesettings: [String: Typesetting]

    /// The screen last adjusted, whose typesetting a screen seen for the first time starts from.
    @ObservationIgnored
    private var lastAdjusted: String?

    /// What a screen starts from where none has been adjusted yet.
    @ObservationIgnored
    private let firstTypesetting: Typesetting

    /// How the text is set on a screen.
    func typesetting(for screen: ReadingScreen) -> Typesetting {
        typesettings[screen.id] ?? lastAdjusted.flatMap { typesettings[$0] } ?? firstTypesetting
    }

    /// Keeps a screen's own copy of how it is set the first time it is seen, so adjusting another
    /// screen later doesn't move this one.
    func adopt(_ screen: ReadingScreen) {
        guard screen.isKnown, typesettings[screen.id] == nil else { return }

        typesettings[screen.id] = typesetting(for: screen)
        keepTypesettings()
    }

    /// Changes how the text is set on one screen.
    func adjust(_ screen: ReadingScreen, _ change: (inout Typesetting) -> Void) {
        let was = typesetting(for: screen)
        var typesetting = was

        change(&typesetting)

        // A face that hasn't got the weight in hand would silently draw another one.
        if !typesetting.face.weights.contains(typesetting.weight) { typesetting.weight = .regular }

        guard typesetting != was else { return }

        if typesetting.margins != was.margins { settleMargins(on: screen, from: was.margins) }

        typesettings[screen.id] = typesetting
        lastAdjusted = screen.id
        keepTypesettings()
    }

    /// The margin a screen's page is actually set to, which follows the slider rather than keeping up
    /// with it.
    ///
    /// Setting a book costs a pass over the whole of it, and a slider dragged across its range would ask
    /// for one at every step. The page waits until the reader has stopped moving it.
    func settledMargins(on screen: ReadingScreen) -> Double {
        unsettledMargins[screen.id] ?? typesetting(for: screen).margins
    }

    /// The margins a screen's page stays at while its slider is moving.
    private var unsettledMargins: [String: Double] = [:]

    @ObservationIgnored
    private var marginSettling: [String: Task<Void, Never>] = [:]

    private func settleMargins(on screen: ReadingScreen, from margins: Double) {
        if unsettledMargins[screen.id] == nil { unsettledMargins[screen.id] = margins }

        marginSettling[screen.id]?.cancel()
        marginSettling[screen.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.marginsSettle))

            guard !Task.isCancelled, let self else { return }

            unsettledMargins[screen.id] = nil
        }
    }

    /// How long the reader has to leave the slider alone before the book is set again.
    static let marginsSettle: Double = 2

    private func keepTypesettings() {
        defaults.set(try? JSONEncoder().encode(typesettings), forKey: Keys.typesettings)
        defaults.set(lastAdjusted, forKey: Keys.lastAdjusted)
    }

    /// A typesetting with whatever the launch arguments name laid over it, which is how a test or
    /// `simctl` sets the page without touching the form. Laid over at launch only, so the form still
    /// moves what they set.
    private static func driven(_ kept: Typesetting, by launchArguments: [String: Any]) -> Typesetting {
        guard !launchArguments.isEmpty else { return kept }

        var typesetting = kept
        let number = { (key: String) in launchArguments[key].flatMap { Double("\($0)") } }
        let text = { (key: String) in launchArguments[key].map { "\($0)" } }

        if let value = number(Keys.fontSize) { typesetting.fontSize = value }
        if let value = number(Keys.lineSpacing) { typesetting.lineSpacing = value }
        if let value = number(Keys.letterSpacing) { typesetting.letterSpacing = value }
        if let value = number(Keys.margins) { typesetting.margins = value }
        if let value = text(Keys.face).flatMap(Face.init(rawValue:)) { typesetting.face = value }
        if let value = text(Keys.weight).flatMap(Weight.init(rawValue:)) { typesetting.weight = value }
        if let value = text(Keys.russianAlignment).flatMap(Alignment.init(rawValue:)) {
            typesetting.russianAlignment = value
        }
        if let value = text(Keys.englishAlignment).flatMap(Alignment.init(rawValue:)) {
            typesetting.englishAlignment = value
        }
        if let value = text(Keys.hyphenates) { typesetting.hyphenates = value == "YES" || value == "1" }

        return typesetting
    }

    /// True where the page turns with the system: one theme for its light hours and another for its
    /// dark ones. Off, the page keeps one theme whatever the system is doing.
    var followsSystem: Bool {
        didSet { defaults.set(followsSystem, forKey: Keys.followsSystem) }
    }

    var lightTheme: Theme {
        didSet { defaults.set(lightTheme.rawValue, forKey: Keys.lightTheme) }
    }

    var darkTheme: Theme {
        didSet { defaults.set(darkTheme.rawValue, forKey: Keys.darkTheme) }
    }

    /// The page's theme where it does not follow the system.
    var fixedTheme: Theme {
        didSet { defaults.set(fixedTheme.rawValue, forKey: Keys.theme) }
    }

    /// What the system is showing, told by the screen that is showing it. Not kept: the system says it
    /// afresh every launch, and a stale answer would show as the page opening in the wrong colours.
    var systemIsDark = false

    /// The page's colours, whichever way the reader settled them.
    var theme: Theme {
        guard followsSystem else { return fixedTheme }

        return systemIsDark ? darkTheme : lightTheme
    }

    /// The theme a page takes under a system showing light or dark, whatever this has been told so far.
    func theme(underDarkSystem isDark: Bool) -> Theme {
        guard followsSystem else { return fixedTheme }

        return isDark ? darkTheme : lightTheme
    }

    /// A tap on the left of the page turns forward, as a tap on the right does.
    ///
    /// Off, the two sides part: the left goes back a page and the right goes on. Which one a reader
    /// wants depends on the hand they hold the book in, so the app holds an opinion and lets it go.
    var advancesOnLeftTap: Bool {
        didSet { defaults.set(advancesOnLeftTap, forKey: Keys.advancesOnLeftTap) }
    }

    /// Draws every picture in the page's own two colours, colour art included.
    ///
    /// Line art and scans take them anyway, since a sheet of white paper in the middle of a night page
    /// reads worse than the text around it. This holds the rest to them too.
    var monochromeImages: Bool {
        didSet { defaults.set(monochromeImages, forKey: Keys.monochromeImages) }
    }

    /// Holds the page upright however the device is held, which is what reading lying down asks for.
    var isPortraitOnly: Bool {
        didSet {
            defaults.set(isPortraitOnly, forKey: Keys.portraitOnly)
            OrientationLock.apply(portraitOnly: isPortraitOnly)
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var watching: (any UITraitChangeRegistration)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let launchArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)

        let kept =
            defaults.data(forKey: Keys.typesettings)
            .flatMap { try? JSONDecoder().decode([ String: Typesetting ].self, from: $0) } ?? [:]

        typesettings = kept.mapValues { Self.driven($0, by: launchArguments) }
        lastAdjusted = defaults.string(forKey: Keys.lastAdjusted)
        firstTypesetting = Self.driven(Self.typesettingKeptOnce(in: defaults), by: launchArguments)
        // "system" was a theme of its own before it was a switch, and it meant exactly what the switch
        // does. A reader who chose it keeps what they chose.
        let stored = defaults.string(forKey: Keys.theme)

        fixedTheme = stored.flatMap(Theme.init(rawValue:)) ?? .paper
        followsSystem =
            defaults.object(forKey: Keys.followsSystem) == nil
            ? stored == nil || stored == "system"
            : defaults.bool(forKey: Keys.followsSystem)
        lightTheme = defaults.string(forKey: Keys.lightTheme).flatMap(Theme.init(rawValue:)) ?? .paper
        darkTheme = defaults.string(forKey: Keys.darkTheme).flatMap(Theme.init(rawValue:)) ?? .night
        advancesOnLeftTap =
            defaults.object(forKey: Keys.advancesOnLeftTap) == nil
            || defaults.bool(forKey: Keys.advancesOnLeftTap)
        monochromeImages = defaults.bool(forKey: Keys.monochromeImages)
        isPortraitOnly = defaults.bool(forKey: Keys.portraitOnly)
        OrientationLock.seed(portraitOnly: isPortraitOnly)
        // Before there is a scene to ask, so the first page isn't set light and then again dark.
        systemIsDark = UITraitCollection.current.userInterfaceStyle == .dark
    }

    /// Follows what the system is showing, for as long as this is held.
    func watchTheSystem() {
        guard watching == nil else { return }

        watching = SystemAppearance.watch { [weak self] isDark in self?.systemIsDark = isDark }
    }

    /// Asked again where nothing was there to be asked before, and whenever the app has been away long
    /// enough for the system to have turned without it.
    func readTheSystem() {
        systemIsDark = SystemAppearance.isDark
        watchTheSystem()
    }

    /// Everything the layout engine needs on a screen; changing any of it invalidates pagination.
    func textStyle(on screen: ReadingScreen) -> ChapterTextStyle {
        let typesetting = typesetting(for: screen)

        return ChapterTextStyle(
            face: typesetting.face,
            weight: typesetting.weight,
            fontSize: typesetting.fontSize,
            lineSpacing: typesetting.lineSpacing,
            letterSpacing: typesetting.letterSpacing,
            justifiesRussian: typesetting.russianAlignment == .justified,
            justifiesEnglish: typesetting.englishAlignment == .justified,
            hyphenates: typesetting.hyphenates,
            textColor: UIColor(theme.foreground),
            backgroundColor: UIColor(theme.background),
            monochromeImages: monochromeImages
        )
    }

    /// The style a page is set in, which is everything but its colours: those are laid on when the
    /// page is drawn, so the theme turning doesn't set the book again.
    func layoutStyle(on screen: ReadingScreen) -> ChapterTextStyle {
        var style = textStyle(on: screen)

        style.textColor = .black
        style.backgroundColor = .white
        return style
    }

    /// How the text was set before it was set for each screen apart, which is where every screen starts.
    private static func typesettingKeptOnce(in defaults: UserDefaults) -> Typesetting {
        let size = defaults.double(forKey: Keys.fontSize)
        let spacing = defaults.double(forKey: Keys.lineSpacing)

        return Typesetting(
            fontSize: size > 0 ? size : 19,
            lineSpacing: spacing > 0 ? spacing : 7,
            letterSpacing: defaults.double(forKey: Keys.letterSpacing),
            // `double(forKey:)` reads 0 for a missing value, and 0 is a margin a reader may choose.
            margins: defaults.object(forKey: Keys.margins) == nil ? 24 : defaults.double(forKey: Keys.margins),
            face: defaults.string(forKey: Keys.face).flatMap(Face.init(rawValue:)) ?? .serif,
            weight: defaults.string(forKey: Keys.weight).flatMap(Weight.init(rawValue:)) ?? .regular,
            russianAlignment:
                defaults.string(forKey: Keys.russianAlignment).flatMap(Alignment.init(rawValue:)) ?? .justified,
            englishAlignment:
                defaults.string(forKey: Keys.englishAlignment).flatMap(Alignment.init(rawValue:)) ?? .leading,
            hyphenates: defaults.object(forKey: Keys.hyphenates) == nil || defaults.bool(forKey: Keys.hyphenates)
        )
    }

    private enum Keys {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let letterSpacing = "reader.letterSpacing"
        static let margins = "reader.margins"
        static let face = "reader.face"
        static let weight = "reader.weight"
        static let russianAlignment = "reader.alignment.ru"
        static let englishAlignment = "reader.alignment.en"
        static let theme = "reader.theme"
        static let followsSystem = "reader.theme.followsSystem"
        static let lightTheme = "reader.theme.light"
        static let darkTheme = "reader.theme.dark"
        static let hyphenates = "reader.hyphenates"
        static let advancesOnLeftTap = "reader.advancesOnLeftTap"
        static let monochromeImages = "reader.monochromeImages"
        static let portraitOnly = "reader.portraitOnly"
        static let typesettings = "reader.typesettings"
        static let lastAdjusted = "reader.typesettings.lastAdjusted"
    }
}
