import ClipboardClient
import ComposableArchitecture
import Database
import FixtureTeamResolution
import Foundation
import GameAnalysis
import GameCore
import SwiftUI

package struct BulkGamesPreview: View {
  @Bindable var store: StoreOf<BulkGamesFeature>
  package var body: some View {
    List {
      Section(store.rows.count == 1 ? "1 game" : "\(store.rows.count) games") {
        ForEach(store.rows) { row in
          BulkGamesPreviewRow(store: store, row: row)
            .contextMenu {
              Button("Delete", systemImage: "trash", role: .destructive) {
                store.send(.deleteGame(row.id))
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button("Delete", systemImage: "trash", role: .destructive) {
                store.send(.deleteGame(row.id))
              }
            }
        }
      }
      if let error = store.errorMessage {
        Section { Text(error).foregroundStyle(.red) }
      }
      if let message = store.validationMessage {
        Section { Text(message).foregroundStyle(.orange) }
      }
    }
    .disabled(store.isSaving)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if !store.canSave, !store.isSaving {
          Text(store.validationMessage ?? "Resolve the highlighted details to save.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Button {
          store.send(.saveButtonTapped)
        } label: {
          HStack {
            if store.isSaving {
              ProgressView()
            }
            Text(store.isSaving ? "Saving…" : "Save All (\(store.rowsToSave.count))")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!store.canSave)
        .accessibilityIdentifier("bulkGames.saveAll")
        Text("\(store.newTeamCount) new teams")
          .font(.caption).foregroundStyle(.secondary)
      }
      .padding()
      .background(.bar)
    }
  }
}

#Preview {
  BulkGamesPreview(
    store: Store(initialState: BulkGamesFeature.State()) { BulkGamesFeature() }
  )
}
