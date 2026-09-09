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

    var body: some View {
        Section {
            if let folder = backup.folderName {
                LabeledContent {
                    Text(folder)
                } label: {
                    Label("Folder", systemImage: "folder")
                }

                if let written = backup.writtenAt {
                    LabeledContent {
                        Text(written, format: .relative(presentation: .named))
                    } label: {
                        Label("Last backed up", systemImage: "clock")
                    }
                }

                Button {
                    Task { await backup.backUp() }
                } label: {
                    Label("Back up now", systemImage: "arrow.up.circle")
                }
                .disabled(backup.isWorking)
                .accessibilityIdentifier("backup.write")

                Button(role: .destructive) {
                    isConfirmingRestore = true
                } label: {
                    Label("Restore from this folder", systemImage: "arrow.down.circle")
                }
                .disabled(backup.isWorking)
                .accessibilityIdentifier("backup.restore")

                Button("Forget this folder") { backup.forget() }
                    .disabled(backup.isWorking)
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
    }

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
