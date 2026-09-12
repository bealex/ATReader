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
                    authorToday
                    otherSources
                    BackupSection()
                    other
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

        /// The service: who is signed in and the way out, and what its shelf shows.
        private var authorToday: some View {
            Section {
                if let user = session.user { profileRow(user) }

                Toggle(isOn: shelfBinding) {
                    Label("Show likes", systemImage: "heart")
                }
                .accessibilityIdentifier("profile.showsLikes")
                .accessibilityHint("Shows how many readers liked each book")
            } header: {
                Text(verbatim: "Author.Today")
            } footer: {
                // Kept to one literal: splitting it would stop it being a localizable key.
                Text("Books you are reading are checked daily; new chapters download and badge the icon.")
            }
        }

        /// Books from anywhere but the service: a file, or the reader's Litres shelf.
        private var otherSources: some View {
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

                LitresRows { Task { await refreshStats() } }
            } header: {
                ExplainedHeader(
                    Text("Other sources"),
                    explanation: Text(
                        """
                        Books from an FB2 file or from Litres live on this device alone, along with the files \
                        they came in. Clearing downloads doesn't touch them, because nothing could send them \
                        again. Back them up to keep a copy.

                        Litres books come across once. The app doesn't check the service again, and the \
                        session ends when they arrive.
                        """
                    )
                )
            }
        }

        /// How the page looks, what the device keeps of the books, and in debug builds the catalogue.
        private var other: some View {
            Section {
                Button {
                    navigator.push(.readerAppearance)
                } label: {
                    DisclosureLabel { Label("Reader appearance", systemImage: "textformat.size") }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Font and page settings for reading")

                LabeledContent {
                    RowStack(spacing: Design.Space.medium) {
                        Text(cacheSize, format: .byteCount(style: .file))

                        Button(role: .destructive) {
                            isConfirmingClear = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .tint(Design.Palette.alert)
                        .accessibilityLabel("Clear downloads")
                        .accessibilityIdentifier("profile.clearDownloads")
                        .accessibilityHint("Removes chapters stored for offline reading")
                    }
                } label: {
                    Label("Books", systemImage: "arrow.down.circle")
                }
                .accessibilityElement(children: .contain)

                #if DEBUG
                    // The token catalogue. Its label is verbatim because a token name isn't translated.
                    Button {
                        navigator.push(.designSystem)
                    } label: {
                        DisclosureLabel {
                            Label {
                                Text(verbatim: "Design System")
                            } icon: {
                                Image(systemName: "ruler")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.designSystem")
                #endif
            } header: {
                Text("Other")
            }
        }

        /// Who is signed in, and the way out, centred on the avatar.
        private func profileRow(_ user: UserInfo) -> some View {
            HStack(spacing: Design.Space.medium) {
                account(user)

                Button(role: .destructive) {
                    isConfirmingSignOut = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .tint(Design.Palette.alert)
                .accessibilityLabel("Sign out")
                .accessibilityIdentifier("profile.signOut")
                .accessibilityHint("Removes the stored token and returns to the sign-in screen")
            }
            .padding(.vertical, Design.Space.small)
        }

        private func account(_ user: UserInfo) -> some View {
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

                    if let checked = UpdateBadge.lastCheckedAt {
                        RowStack(spacing: Design.Space.extraSmall) {
                            Text("Last checked for updates")
                            Text(checked, format: .relative(presentation: .named))
                        }
                        .font(Design.Style.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
