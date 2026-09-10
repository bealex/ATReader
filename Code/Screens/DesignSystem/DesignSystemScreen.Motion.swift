//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// The half of the catalogue that only exists while it is moving.
///
/// Nothing here can be read off a drawing or off the code: what is written is a spring, and what matters
/// is what it does. Every specimen runs on the device, at the speed it runs in the app, and each carries
/// the control that starts it. The books are the library's own views rather than drawings of them, so a
/// specimen that looks right is the shelf looking right.
extension DesignSystemScreen.Component {
    var motionSpecimens: some View {
        VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
            card(
                "Fold",
                "A book turning between the edge it stands on and the face it's taken down for. "
                    + "The hinge is the spine's outer edge, and the cover is folded in behind it."
            ) {
                VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                    specimen("Turning, \(Self.seconds(FoldMotion.turningSeconds))") {
                        TurningBook()
                    }

                    specimen("The turn, held still") {
                        HStack(alignment: .bottom, spacing: Design.Space.medium) {
                            ForEach([ 0.0, 0.25, 0.5, 0.75, 1.0 ], id: \.self) { turned in
                                DrawnBook(turned: turned, width: Design.Size.cover)
                            }
                        }
                        .accessibilityIdentifier("catalog.fold.strip")
                    }

                    specimen("A whole card, which is what the library is made of") {
                        DrawnCard()
                    }

                    specimen("The library's own list, cards and all") {
                        DrawnLibrary()
                    }
                }
            }

            card(
                "Aside",
                "How a note arrives and leaves. Out of the point it hangs on and back into it, with a "
                    + "bounce on the way out and none on the way back."
            ) {
                specimen(
                    "Showing \(Self.seconds(CalloutMotion.showingSeconds)), "
                        + "hiding \(Self.seconds(CalloutMotion.hidingSeconds))"
                ) {
                    AsideSpecimen()
                }
            }
        }
    }

    private static func seconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 2))))s"
    }
}

/// A book turning between its edge and its face, with the turn under the reader's own finger.
private struct TurningBook: View {
    @State
    private var turned: CGFloat = 0

    private var width: CGFloat { Design.Size.coverLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.large) {
            DrawnBook(turned: turned, width: width)
                .frame(height: Design.Size.coverHeight(width: width), alignment: .bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("catalog.fold.book")

            controls
        }
    }

    private var controls: some View {
        HStack(spacing: Design.Space.large) {
            Button {
                withAnimation(FoldMotion.turning) { turned = turned > 0.5 ? 0 : 1 }
            } label: {
                Text(verbatim: turned > 0.5 ? "Shelve" : "Take down")
                    .frame(width: Design.Size.avatar * 2)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("catalog.fold.turn")

            Slider(value: $turned, in: 0 ... 1)
                .accessibilityLabel(Text(verbatim: "How far the book has turned"))
                .accessibilityIdentifier("catalog.fold.turned")
        }
    }
}

/// One moment of the turn, drawn by the library's own book rather than by a stand-in for it.
private struct DrawnBook: UIViewRepresentable {
    let turned: CGFloat
    let width: CGFloat

    private var standing: CGFloat { Design.Size.coverHeight(width: width) }

    private var edge: CGFloat { Shelf.spineWidth(of: Specimen.book, cover: width) }

    func makeUIView(context: Context) -> BookView { BookView() }

    func updateUIView(_ view: BookView, context: Context) {
        view.show(BookView.Contents(
            stands: .book(
                Specimen.book,
                number: 3,
                title: "Second Winter",
                marks: CoverView.Marks(progress: 0.47, origin: .service)
            ),
            edge: edge,
            face: width,
            standing: standing,
            box: standing
        ))
        view.turned = turned
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BookView, context: Context) -> CGSize? {
        CGSize(width: Hinge(edge: edge, face: width, turned: turned).width, height: standing)
    }
}

/// One author's card, drawn by the library's own views, with a control to turn the shelf round.
private struct DrawnCard: View {
    @State
    private var showsEveryCover = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.large) {
            Card(showsEveryCover: showsEveryCover)
                .frame(height: AuthorCardView.height(Specimen.card(showsEveryCover), across: Card.width))
                .frame(width: Card.width)

            Button {
                withAnimation(FoldMotion.turning) { showsEveryCover.toggle() }
            } label: {
                Text(verbatim: showsEveryCover ? "Shelve the read ones" : "Take them all down")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("catalog.shelf.turn")
        }
    }

    /// The card itself, which is the library's own view rather than a drawing of it.
    private struct Card: UIViewRepresentable {
        let showsEveryCover: Bool

        /// What the catalogue gives a card, which is about what the library gives one on a phone.
        static let width = Design.Space.unit * 106

        func makeUIView(context: Context) -> AuthorCardView { AuthorCardView() }

        func updateUIView(_ view: AuthorCardView, context: Context) {
            view.turn(to: Specimen.card(showsEveryCover), animated: context.transaction.animation != nil)
        }
    }
}

/// The library's list itself, with invented authors on it, so the one screen that needs a signed-in
/// account to reach can be looked at without one.
private struct DrawnLibrary: View {
    @State
    private var open: Set<String> = []

    var body: some View {
        LibraryList(
            cards: Specimen.shelves.map { Specimen.card($0, showsEveryCover: open.contains($0)) },
            chrome: LibraryList.Chrome(search: "", onSearch: { _ in }, empty: nil),
            onOpen: { _, _ in },
            onName: { turn($0) },
            onTurn: { turn($0) },
            bookMenu: { _ in nil },
            runMenu: { _ in nil },
            authorMenu: { _ in nil },
            onRefresh: {}
        )
        .frame(height: Design.Space.unit * 150)
        .accessibilityIdentifier("catalog.library")
    }

    private func turn(_ author: String) {
        withAnimation(FoldMotion.turning) {
            if open.contains(author) { open.remove(author) } else { open.insert(author) }
        }
    }
}

/// Everything the catalogue's books are. Invented, and obviously so: nothing the service returned ever
/// goes in the repository.
@MainActor
private enum Specimen {
    /// A cover invented on the spot, so a spine has something to be a blur of and a cover something to
    /// be a picture of. Nothing the service returned ever goes in the repository, this included.
    static let artwork = URL(filePath: "/specimen/cover")

    /// Painted into the shared cache the first time anything asks, since everything that draws a book
    /// reads that cache rather than the network.
    static func paint() {
        guard CoverImages.image(for: artwork) == nil else { return }

        let size = CGSize(width: Design.Space.unit * 100, height: Design.Space.unit * 150)
        let painted = UIGraphicsImageRenderer(size: size).image { context in
            let colours = [ UIColor.systemIndigo.cgColor, UIColor.systemOrange.cgColor ]

            guard
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colours as CFArray,
                    locations: [ 0, 1 ]
                )
            else { return }

            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            UIColor.black.withAlphaComponent(0.7).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.12))
            UIColor.white.withAlphaComponent(0.8).setFill()
            context.fill(CGRect(x: size.width * 0.15, y: size.height * 0.2, width: size.width * 0.5, height: 12))
        }

        CoverImages.remember(painted, for: artwork)
    }

    static let book = Book(
        id: 2,
        title: "Second Winter",
        authorLine: "Author Name",
        coverURL: artwork,
        annotation: nil,
        seriesTitle: "Name of the series",
        textLength: 700_000
    )

    /// Two authors, so a list of them has something to lay out.
    static let shelves = [ "one", "two" ]

    static func card(_ showsEveryCover: Bool) -> AuthorCardView.Contents {
        card("catalogue", showsEveryCover: showsEveryCover)
    }

    static func card(_ id: String, showsEveryCover: Bool) -> AuthorCardView.Contents {
        paint()

        return AuthorCardView.Contents(
            id: id,
            name: "Author Name",
            shelf: ShelfView.Contents(
                runs: [
                    ShelfRun(
                        id: "one",
                        title: "Name of the series",
                        slots: [
                            .book(volume(1, length: 300_000), number: 1, title: "First Winter", isRead: true),
                            .book(volume(2, length: 700_000), number: 2, title: "Second Winter", isRead: true),
                            .missing(3),
                            .book(volume(4, length: 1_200_000), number: 4, title: "Fourth Winter", isRead: false),
                        ]
                    )
                ],
                alone: [ .book(volume(5, length: 500_000), number: nil, title: "On Its Own", isRead: true) ],
                coverWidth: Design.Size.gridCover,
                showsEveryCover: showsEveryCover,
                origin: { _ in .service }
            )
        )
    }

    private static func volume(_ id: Int, length: Int) -> Book {
        Book(
            id: id,
            title: "Title of the book",
            authorLine: "Author Name",
            coverURL: artwork,
            annotation: nil,
            seriesTitle: "Name of the series",
            textLength: length,
            readingProgress: 0.47
        )
    }
}

/// An aside called up off a point and put away again.
private struct AsideSpecimen: View {
    private struct Note: Identifiable {
        let id = 0
    }

    @State
    private var note: Note?

    private var point: CGRect {
        CGRect(origin: CGPoint(x: Design.Size.callout / 2, y: Design.Size.calloutDepth / 2), size: .zero)
    }

    var body: some View {
        ZStack {
            Design.Surface.fill

            Button {
                withAnimation(note == nil ? CalloutMotion.showing : CalloutMotion.hiding) {
                    note = note == nil ? Note() : nil
                }
            } label: {
                Text(verbatim: note == nil ? "Show" : "Hide")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("catalog.motion.aside")
        }
        .frame(width: Design.Size.callout, height: Design.Size.calloutDepth)
        .callout(over: point, item: $note, ground: Self.ground) { _ in
            Callout(text: Self.prose, onClose: { note = nil })
                .accessibilityIdentifier("catalog.motion.aside.presented")
        }
    }

    private static var ground: Color {
        Callout<EmptyView>.surface(over: Design.Surface.card, with: .primary)
    }

    private static let prose = """
        An aside grows out of the point it hangs on and goes back into it, so it reads as that point \
        opening rather than as a card arriving from nowhere.
        """
}
