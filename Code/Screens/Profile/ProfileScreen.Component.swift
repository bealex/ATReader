//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookStorage
import DesignSystem
import SwiftUI

enum ProfileScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @Environment(ReaderSettings.self)
        private var settings

        @Environment(BookInbox.self)
        private var inbox

        @State
        private var isPickingFile = false

        @State
        private var isConfirmingSignOut = false

        @Environment(ShelfSettings.self)
        private var shelf

        @Environment(Navigator.self)
        private var navigator

        @State
        private var isConfirmingClear = false

        @State
        private var cacheSize: Int64 = 0

        /// The setting is a class the view only reads from here, so the toggle is handed a binding
        /// into it rather than the view being rebuilt around one.
        private var shelfBinding: Binding<Bool> {
            Binding {
                shelf.showsLikes
            } set: {
                shelf.showsLikes = $0
            }
        }

        /// What the device is holding, which changes whenever books arrive or are cleared out.
        private func refreshStats() async {
            cacheSize = await SQLiteBookStore.shared.downloadSize() + CoverCache.shared.diskUsage()
        }

        var body: some View {
            List {
                Group {
                    if let user = session.user {
                        Section { profileRow(user) }
                    }

                    Section("Reading") {
                        Button {
                            navigator.push(.readerAppearance)
                        } label: {
                            DisclosureLabel { Label("Reader appearance", systemImage: "textformat.size") }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Font and page settings for reading")
                    }

                    Section {
                        Toggle(isOn: shelfBinding) {
                            Label("Show likes", systemImage: "heart")
                        }
                        .accessibilityIdentifier("profile.showsLikes")
                        .accessibilityHint("Shows how many readers liked each book")
                    } header: {
                        Text("Shelf")
                    } footer: {
                        Text("How many people liked a book, on its row and its page.")
                    }

                    Section {
                        LabeledContent {
                            Text(cacheSize, format: .byteCount(style: .file))
                        } label: {
                            Label("Downloaded books", systemImage: "arrow.down.circle")
                        }
                        .accessibilityLabel("Downloaded books take up \(Int(cacheSize)) bytes")

                        Button("Clear downloads", systemImage: "trash", role: .destructive) {
                            isConfirmingClear = true
                        }
                        .accessibilityIdentifier("profile.clearDownloads")
                        .accessibilityHint("Removes chapters stored for offline reading")

                        if let checked = UpdateBadge.lastCheckedAt {
                            LabeledContent {
                                Text(checked, format: .relative(presentation: .named))
                            } label: {
                                Label("Last checked for updates", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    } header: {
                        Text("Offline")
                    } footer: {
                        // Kept to one literal — splitting it would stop it being a localizable key.
                        Text("Books you are reading are checked daily; new chapters download and badge the icon.")
                    }

                    Section {
                        Button {
                            isPickingFile = true
                        } label: {
                            Label("Add a book from a file", systemImage: "plus")
                        }
                        .disabled(inbox.isImporting)
                        .accessibilityIdentifier("profile.add")
                        .accessibilityHint("Reads an FB2 file into your library")
                        .fileImporter(
                            isPresented: $isPickingFile,
                            allowedContentTypes: LocalBookFiles.fileTypes,
                            allowsMultipleSelection: true
                        ) { result in
                            guard case let .success(urls) = result else { return }

                            Task { await inbox.accept(urls) }
                        }
                    } header: {
                        Text("Your own books")
                    } footer: {
                        Text("An FB2 file is read onto the shelf and kept on this device alone.")
                    }

                    LitresSection { Task { await refreshStats() } }

                    BackupSection()

                    Section {
                        Button(role: .destructive) {
                            isConfirmingSignOut = true
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .accessibilityIdentifier("profile.signOut")
                        .accessibilityHint("Removes the stored token and returns to the sign-in screen")
                    } footer: {
                        Text("Your token is kept in the device keychain and removed when you sign out.")
                    }
                }
                .listRowBackground(Design.Surface.card)
            }
            .listOnScreen()
            .navigationTitle("Profile")
            .task {
                await refreshStats()
                await UpdateBadge.requestBadgePermission()
            }
            .confirmationDialog(
                "Clear downloads?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible,
                actions: {
                    Button("Yes, clear them", role: .destructive) {
                        Task {
                            await SQLiteBookStore.shared.clearDownloads()
                            await CoverCache.shared.clear()
                            await refreshStats()
                        }
                    }
                    Button("Cancel", role: .cancel, action: {})
                },
                message: {
                    Text(
                        "Chapters saved for reading offline are removed and downloaded again when you next open them. Books you imported are kept."
                    )
                }
            )
            .confirmationDialog(
                "Sign out?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible,
                actions: {
                    Button("Yes, sign out", role: .destructive) { session.signOut() }
                    Button("Cancel", role: .cancel, action: {})
                }
            )
        }

        private func profileRow(_ user: UserInfo) -> some View {
            HStack(spacing: Design.Space.large) {
                avatar(user)

                VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                    Text(user.displayName)
                        .font(Design.Style.heading)

                    if let userName = user.userName, !userName.isEmpty {
                        Text("@\(userName)")
                            .font(Design.Style.label)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Design.Space.small)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Signed in as \(user.displayName)")
        }

        private func avatar(_ user: UserInfo) -> some View {
            AsyncImage(url: user.avatarURL) { image in
                image
                    .resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Design.Size.avatar, height: Design.Size.avatar)
            .clipShape(.circle)
            .accessibilityHidden(true)
        }
    }
}
