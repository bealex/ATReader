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

    var body: some View {
        Section {
            if let folder = backup.folderName {
                LabeledContent {
                    RowStack(spacing: Design.Space.medium) {
                        VStack(alignment: .trailing, spacing: Design.Space.extraSmall) {
                            Text(folder)

                            if let bytes = backup.bytes {
                                Text(bytes, format: .byteCount(style: .file))
                                    .font(Design.Style.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

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
                } label: {
                    Label("Folder", systemImage: "folder")
                }

                LabeledContent {
                    RowStack(spacing: Design.Space.medium) {
                        if let written = backup.writtenAt { Self.age(of: written) }

                        Button {
                            Task { await backup.backUp() }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(backup.isWorking)
                        .accessibilityLabel("Back up now")
                        .accessibilityIdentifier("backup.write")
                    }
                } label: {
                    Label("Last:", systemImage: "clock")
                }
                .lineLimit(1)

                Button(role: .destructive) {
                    isConfirmingRestore = true
                } label: {
                    Label("Restore from this folder", systemImage: "arrow.down.circle")
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
            Text("Backup")
        } footer: {
            Text("Books you imported live only on this device. A folder in iCloud Drive keeps a copy.")
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [ .folder ]) { result in
            guard case let .success(folder) = result else { return }

            backup.choose(folder)
        }
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
            case .idle:
                EmptyView()
            case .working:
                RowStack(spacing: Design.Space.medium) {
                    ProgressView()
                    Text("Working…")
                }
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
