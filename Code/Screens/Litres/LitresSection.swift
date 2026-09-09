//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import Litres
import SwiftUI

/// Litres, as it stands in the reader's profile: whether they are signed in, and the one button that
/// brings their books across.
///
/// Everything but signing in happens here. A web view is the only way to sign in, since the service
/// hands its session to a browser and signs it with a key nobody else has, but there is no reason to
/// stand in front of one to fetch a book.
struct LitresSection: View {
    /// Called once a run has finished, for whatever else on the screen counts what the device holds.
    var onLibraryChanged: () -> Void = {}

    @Environment(LitresStore.self)
    private var store

    @State
    private var sync = LitresSync()

    @State
    private var isSigningIn = false

    @State
    private var report: SharedReport?

    var body: some View {
        Section {
            standing

            if store.isSignedIn {
                Button {
                    Task { await bringBooks() }
                } label: {
                    Label("Bring my books across", systemImage: "arrow.down.circle")
                }
                .disabled(sync.isRunning)
                .accessibilityIdentifier("litres.sync")
            } else {
                Button {
                    isSigningIn = true
                } label: {
                    Label("Sign in to Litres", systemImage: "person.crop.circle")
                }
                .disabled(sync.isRunning)
                .accessibilityIdentifier("litres.signIn")
            }

            // Offered the moment there is anything to explain: a count says a run went wrong and
            // nothing about what to do next.
            if sync.hasSomethingToReport {
                Button {
                    report = sync.writeReport().map(SharedReport.init)
                } label: {
                    Label("Share the report", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("litres.report.share")
            }
        } header: {
            Text("Other libraries")
        } footer: {
            Text("Your books come across once. Litres isn't watched afterwards, and the session ends when they arrive.")
        }
        .sheet(isPresented: $isSigningIn) { LitresLoginScreen.Component() }
        .sheet(item: $report) { ShareSheet(url: $0.url) }
    }

    /// Where the run has got to, or what it came to, or nothing at all before one has been asked for.
    @ViewBuilder
    private var standing: some View {
        switch sync.stage {
            case .idle:
                if store.isSignedIn {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            case .reading:
                RowStack(spacing: Design.Space.medium) {
                    ProgressView()
                    Text("Reading your library…")
                }
            case let .working(done, total, title):
                VStack(alignment: .leading, spacing: Design.Space.small) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))

                    Text("\(done) of \(total)")
                        .font(Design.Style.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(Design.Style.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            case let .done(report):
                Label(Self.summary(report), systemImage: "checkmark.circle")
                    .accessibilityIdentifier("litres.report")
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Design.Palette.alert)
                    .accessibilityIdentifier("litres.failure")
        }
    }

    /// Signing in's whole point: the books come across, and then the session has nothing left to do.
    private func bringBooks() async {
        guard let session = store.session else { return }

        await sync.bringEverything(as: session)

        // The shelf hears from the sync itself; what stands beside this on the screen does not.
        onLibraryChanged()

        // Held only for as long as it was needed. A run that failed keeps it, so the reader can try
        // again without signing in twice.
        if case .done = sync.stage { store.signOut() }
    }

    private static func summary(_ report: LitresSync.Report) -> String {
        var parts = [
            String(localized: "\(report.added) added"),
            String(localized: "\(report.updated) updated"),
            String(localized: "\(report.alreadyHere) already here"),
        ]

        if report.failed > 0 { parts.append(String(localized: "\(report.failed) failed")) }
        if report.notBooks > 0 { parts.append(String(localized: "\(report.notBooks) not readable")) }

        return parts.joined(separator: ", ")
    }
}

/// A written report on its way out of the app.
struct SharedReport: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}
