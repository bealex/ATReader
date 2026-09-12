//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// Keeping the library in a folder the reader chose, and putting it back from there.
///
/// A folder rather than the device's own backup, which the store stays out of deliberately. Books
/// imported from a file are the reason it matters: nothing else on the device holds them.
struct BackupSection: View {
    @Environment(LibraryBackup.self)
    private var backup

    @State
    private var isChoosingFolder = false

    @State
    private var isConfirmingRestore = false

    @State
    private var isConfirmingForget = false

    /// A folder picked to take the current one's place, held until the reader confirms it.
    @State
    private var replacement: URL?

    var body: some View {
        Section {
            if let folder = backup.folderPath {
                folderRow(folder)

                // One row, whether a backup is running or was: a second row appearing under it moves
                // everything below out from under the finger that asked for it.
                if backup.isWorking {
                    LabeledContent {
                        ProgressView()
                    } label: {
                        Label("Working:", systemImage: "clock")
                    }
                    .lineLimit(1)
                    .accessibilityIdentifier("backup.working")
                } else {
                    LabeledContent {
                        RowStack(spacing: Design.Space.medium) {
                            if let written = backup.writtenAt { Self.age(of: written) }

                            Button {
                                Task { await backup.backUp() }
                            } label: {
                                Image(systemName: "arrow.clockwise.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Back up now")
                            .accessibilityIdentifier("backup.write")
                        }
                    } label: {
                        Label("Last:", systemImage: "clock")
                    }
                    .lineLimit(1)
                }

                Button(role: .destructive) {
                    isConfirmingRestore = true
                } label: {
                    Label("Restore books from backup", systemImage: "arrow.down.circle")
                }
                .disabled(backup.isWorking)
                .accessibilityIdentifier("backup.restore")
            } else {
                Button {
                    isChoosingFolder = true
                } label: {
                    Label("Choose a folder", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("backup.choose")
            }

            standing
        } header: {
            ExplainedHeader(
                Text("Backup"),
                explanation: Text(
                    """
                    A backup copies your whole library into a Bookhold folder inside the one you chose: \
                    the shelf, reading positions, saved chapters, and every book from a file or from Litres. \
                    The app writes one only when you ask, and rewrites a book's files only when they've \
                    changed.

                    Restoring replaces everything on this device with what the folder holds, so you lose \
                    anything added since that backup. Pick a folder in iCloud Drive and the library \
                    survives losing the device.
                    """
                )
            )
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [ .folder ]) { result in
            guard case let .success(folder) = result else { return }

            // Only a folder already holding a backup is worth a question; nothing is lost leaving any other.
            if backup.writtenAt != nil, !backup.isCurrent(folder) {
                replacement = folder
            } else {
                backup.choose(folder)
            }
        }
        .confirmationDialog(
            "Use another folder?",
            isPresented: Binding {
                replacement != nil
            } set: {
                if !$0 { replacement = nil }
            },
            titleVisibility: .visible,
            presenting: replacement,
            actions: { folder in
                Button("Yes, use the new one") { backup.choose(folder) }
                Button("Cancel", role: .cancel, action: {})
            },
            message: { _ in
                Text("The backup in the current folder stays there, and nothing is written to it from now on.")
            }
        )
        .confirmationDialog(
            "Restore from this folder?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible,
            actions: {
                Button("Yes, restore", role: .destructive) {
                    Task { await backup.restore() }
                }
                Button("Cancel", role: .cancel, action: {})
            },
            message: {
                Text(
                    // A localisation key: wrapped, it would be a different one.
                    // swiftlint:disable:next line_length
                    "Everything on this device is replaced by what the folder holds. Anything added since that backup is lost."
                )
            }
        )
        .confirmationDialog(
            "Forget this folder?",
            isPresented: $isConfirmingForget,
            titleVisibility: .visible,
            actions: {
                Button("Yes, forget it", role: .destructive) { backup.forget() }
                Button("Cancel", role: .cancel, action: {})
            }
        )
    }

    /// The folder on one line: its path, cut from the front so the folder's own name stays, and how
    /// much the backup in it holds.
    private func folderRow(_ folder: String) -> some View {
        RowStack(spacing: Design.Space.medium) {
            Button {
                isChoosingFolder = true
            } label: {
                RowStack(spacing: Design.Space.medium) {
                    Label {
                        RowStack(spacing: Design.Space.extraSmall) {
                            Text("Folder:")
                                .fixedSize()

                            Text(folder)
                                .foregroundStyle(.secondary)
                                .truncationMode(.head)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .lineLimit(1)

                    Spacer(minLength: 0)

                    if let bytes = backup.bytes {
                        Text(bytes, format: .byteCount(style: .file))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .contentShape(.rect)
            }
            // Plain, so the row's other button stays a target of its own.
            .buttonStyle(.plain)
            .disabled(backup.isWorking)
            .accessibilityHint("Chooses another folder")
            .accessibilityIdentifier("backup.folder")

            Button(role: .destructive) {
                isConfirmingForget = true
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .tint(Design.Palette.alert)
            .disabled(backup.isWorking)
            .accessibilityLabel("Forget this folder")
            .accessibilityIdentifier("backup.forget")
        }
        .accessibilityElement(children: .contain)
    }

    /// How long ago the backup was written, to the nearest unit: "≈ 5 min", "≈ 2 hr".
    private static func age(of written: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let elapsed = context.date.timeIntervalSince(written)

            if elapsed < 60 {
                Text("Just now")
            } else {
                Text("≈ \(Self.roughly.string(from: elapsed) ?? "")")
            }
        }
        .accessibilityLabel(Text(written, format: .relative(presentation: .named)))
    }

    private static let roughly: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [ .minute, .hour, .day, .weekOfMonth, .month, .year ]

        return formatter
    }()

    @ViewBuilder
    private var standing: some View {
        switch backup.stage {
            // A backup running says so in the row it will report in, rather than in one of its own.
            case .idle, .working:
                EmptyView()
            case let .done(what):
                Label(what, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("backup.report")
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Design.Palette.alert)
                    .accessibilityIdentifier("backup.failure")
        }
    }
}
