//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

enum TopScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @State
        private var model: Model?

        @State
        private var path: [AppRoute] = []

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if let model {
                        content(model)
                    } else {
                        Color.clear
                    }
                }
                .navigationTitle("Top books")
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            }
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
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                ForEach(Array(model.feed.works.enumerated()), id: \.element.id) { position, work in
                    NavigationLink(value: AppRoute.work(id: work.id, title: work.title)) {
                        RankedRow(rank: position + 1, work: work)
                    }
                    .task { await model.feed.loadMoreIfNeeded(currentItem: work) }
                }

                if model.feed.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .accessibilityLabel("Loading more")
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("top.list")
            .refreshable { await model.reload() }
            .overlay {
                if model.feed.isLoading {
                    ProgressView("Building the chart…")
                        .accessibilityLabel("Loading top books")
                } else if let message = model.feed.errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))
                }
            }
        }

        @ViewBuilder
        private func filters(_ model: Bindable<Model>) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Ranking", selection: model.sorting) {
                    ForEach(Model.chartOrders, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Ranking type")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RatingPeriod.allCases, id: \.self) { period in
                            FilterChip(
                                title: period.title,
                                isSelected: model.wrappedValue.period == period,
                                action: { model.wrappedValue.period = period }
                            )
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            title: "All genres",
                            isSelected: model.wrappedValue.genreId == nil,
                            action: { model.wrappedValue.genreId = nil }
                        )

                        ForEach(model.wrappedValue.genres) { genre in
                            FilterChip(
                                title: genre.title,
                                isSelected: model.wrappedValue.genreId == genre.id,
                                action: { model.wrappedValue.genreId = genre.id }
                            )
                        }
                    }
                }
            }
        }
    }

    /// A top-list row: the position, then the usual book row.
    struct RankedRow: View {
        let rank: Int
        let work: WorkSummary

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Text("\(rank)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rank <= 3 ? Color.accentColor : .secondary)
                    .frame(minWidth: 28, alignment: .trailing)
                    .accessibilityHidden(true)

                WorkRow(work: work, showsProgress: false)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rank \(rank). \(work.title), \(work.authorLine)")
        }
    }
}

/// A pill-shaped toggle used by the top-list filters.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.accentColor : Color(.secondarySystemFill),
                    in: .capsule
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [ .isButton, .isSelected ] : .isButton)
        .accessibilityHint("Filters the chart")
    }
}
