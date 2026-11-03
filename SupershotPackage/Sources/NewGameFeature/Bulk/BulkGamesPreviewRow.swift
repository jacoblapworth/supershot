import ClipboardClient
import ComposableArchitecture
import Database
import FixtureTeamResolution
import Foundation
import GameAnalysis
import GameCore
import SwiftUI

package struct BulkGamesPreviewRow: View {
  let store: StoreOf<BulkGamesFeature>
  let row: BulkGamesFeature.Row

  package var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        if !row.setup.division.isEmpty {
          Text("Division \(row.setup.division)").font(.caption)
        }
        if !row.setup.court.isEmpty {
          Text("Court \(row.setup.court)").font(.caption)
        }
      }
      .padding(.horizontal, 16)
      NavigationLink {
        BulkGameEditor(store: store, rowID: row.id)
      } label: {
        GameRow(game: store.state.listItem(for: row))
      }
      .buttonStyle(.plain)
      if store.state.draft(for: row) == nil {
        Label("Review teams or schedule", systemImage: "exclamationmark.circle")
          .font(.caption).foregroundStyle(.orange)
      }
      if let duplicateID = store.state.duplicateGameID(for: row) {
        Label(
          store.existingGames.contains(where: { $0.id == duplicateID })
            ? "Already exists — won’t be added"
            : "Repeated fixture — won’t be added",
          systemImage: "doc.on.doc"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    .contextMenu { deleteButton }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton }
  }

  package var deleteButton: some View {
    Button("Delete", systemImage: "trash", role: .destructive) {
      store.send(.deleteGame(row.id))
    }
  }
}

#Preview {
  List {
    BulkGamesPreviewRow(
      store: Store(initialState: BulkGamesFeature.State()) { BulkGamesFeature() },
      row: .preview
    )
  }
}
