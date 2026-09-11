//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import AuthorTodayBooks
import BookKit
import DesignSystem
import SwiftUI

enum TopScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @State
        private var model: Model?

        @Environment(Navigator.self)
        private var navigator

        var body: some View {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Top books")
            .onAppear {
                if model == nil { model = Model(session: session) }
            }
            .task { await model?.loadIfNeeded() }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            @Bindable var model = model

            List {
                Section {
                    filters($model)
                        .listRowInsets(
                            EdgeInsets(
                                top: Design.Space.medium,
                                leading: Design.Space.extraLarge,
                                bottom: Design.Space.medium,
                                trailing: Design.Space.extraLarge
                            )
                        )
                        .listRowBackground(Color.clear)
                }

                ForEach(Array(model.feed.works.enumerated()), id: \.element.id) { position, work in
                    Button {
                        navigator.push(.work(id: work.id, title: work.title))
                    } label: {
                        RankedRow(rank: position + 1, work: work)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .task { await model.feed.loadMoreIfNeeded(currentItem: work) }
                }

                if model.feed.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Loading more")
                }
            }
            .listStyle(.plain)
            .listOnScreen()
            .accessibilityIdentifier("top.list")
            .refreshable { await model.reload() }
            .overlay {
                if model.feed.isLoading {
                    LoadingCard(title: "Building the chart…", label: "Loading top books")
                } else if let message = model.feed.errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))
                }
            }
        }

        @ViewBuilder
        private func filters(_ model: Bindable<Model>) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.medium) {
                Picker("Ranking", selection: model.sorting) {
                    ForEach(Model.chartOrders, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Ranking type")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Design.Space.medium) {
                        ForEach(RatingPeriod.allCases, id: \.self) { period in
                            FilterChip(
                                title: period.title,
                                isSelected: model.wrappedValue.period == period,
                                hint: String(localized: "Filters the chart"),
                                action: { model.wrappedValue.period = period }
                            )
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Design.Space.medium) {
                        FilterChip(
                            title: String(localized: "All genres"),
                            isSelected: model.wrappedValue.genreId == nil,
                            hint: String(localized: "Filters the chart"),
                            action: { model.wrappedValue.genreId = nil }
                        )

                        ForEach(model.wrappedValue.genres) { genre in
                            FilterChip(
                                title: genre.title,
                                isSelected: model.wrappedValue.genreId == genre.id,
                                hint: String(localized: "Filters the chart"),
                                action: { model.wrappedValue.genreId = genre.id }
                            )
                        }
                    }
                }
            }
        }
    }
}
