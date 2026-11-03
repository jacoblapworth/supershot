import ClipboardClient
import ComposableArchitecture
import Database
import FixtureTeamResolution
import Foundation
import GameAnalysis
import GameCore
import SwiftUI

package struct BulkGamesView: View {
  @Bindable var store: StoreOf<BulkGamesFeature>

  package init(store: StoreOf<BulkGamesFeature>) {
    self.store = store
  }

  package var body: some View {
    NavigationStack {
      Group {
        if store.showsPreview {
          BulkGamesPreview(store: store)
        } else {
          BulkGamesInput(store: store)
        }
      }
      .scrollEdgeEffectStyle(.soft, for: .all)
      .navigationTitle(store.showsPreview ? "Review Games" : "Create Games")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) { store.send(.cancelButtonTapped) }
              .disabled(store.isSaving)
          }
          if store.showsPreview {
            ToolbarItem(placement: .secondaryAction) {
              Button("Edit Text", systemImage: "text.alignleft") { store.send(.backToInput) }
                .disabled(store.isSaving)
            }
          }
        }
    }
    .interactiveDismissDisabled(store.isSaving)
    #if os(macOS)
      .frame(minWidth: 560, idealWidth: 640, minHeight: 600)
    #endif
  }
}

package struct BulkGamesInput: View {
  @Bindable var store: StoreOf<BulkGamesFeature>
  @FocusState private var isSourceFocused: Bool
  package var body: some View {
    Form {
      Section {
        TextEditor(text: $store.source)
          .focused($isSourceFocused)
          .disabled(store.isParsing)
          .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
          .frame(height: 240)
          .accessibilityLabel("Game descriptions")
          .accessibilityIdentifier("bulkGames.source")
      } footer: {
        if let error = store.errorMessage {
          Text(error).foregroundStyle(.red).accessibilityIdentifier("bulkGames.error")
        }
      }

      Button {
        isSourceFocused = false
        store.send(.parseButtonTapped)
      } label: {
        HStack {
          if store.isParsing {
            ProgressView()
          }
          Label(store.isParsing ? "Reading fixtures…" : "Preview Games", systemImage: "sparkles")
        }.frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.isParsing || store.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityIdentifier("bulkGames.preview")
      if !store.rows.isEmpty {
        Button("Return to Previous Preview") { store.send(.showPreview) }
      }
    }
    .task { isSourceFocused = true }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.pasteTapped)
          isSourceFocused = true
        } label: {
          Label("Paste", systemImage: "document.on.clipboard")
        }
        .accessibilityLabel("Paste fixtures")
        .accessibilityIdentifier("bulkGames.paste")
        .disabled(store.isParsing)
      }
    }
  }
}

package struct BulkGameEditor: View {
  @Dependency(\.date.now) var now
  let store: StoreOf<BulkGamesFeature>
  let rowID: Game.ID
  package var body: some View {
    if let row = store.rows.first(where: { $0.id == rowID }) {
      Form {
        BulkTeamEditor(store: store, teamKey: row.firstKey, rowID: row.id, side: .first, title: "First Team")
        BulkTeamEditor(store: store, teamKey: row.secondKey, rowID: row.id, side: .second, title: "Second Team")
        Section("Schedule") {
          DatePicker("Date and time", selection: Binding(get: { row.setup.scheduledAt ?? now }, set: {
            var updated = row
            updated.setup.scheduledAt = $0
            updated.needsScheduleReview = false
            updated.notices = []
            store.send(.updateRow(updated))
          }))
          if row.needsScheduleReview {
            Button("Confirm Date and Time") {
              var updated = row
              updated.setup.scheduledAt = row.setup.scheduledAt ?? now
              updated.needsScheduleReview = false
              updated.notices = []
              store.send(.updateRow(updated))
            }
          }
          ForEach(row.notices, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
        }
        Section("Game Details") {
          TextField("Division", text: textBinding(row, \.division))
          TextField("Court", text: textBinding(row, \.court))
        }
        Section("Timing") {
          Stepper("Quarter: \(row.setup.periodDuration.minutesText) minutes", value: Binding(
            get: { Int(row.setup.periodDuration.minutesText) ?? 10 },
            set: {
              var updated = row
              updated.setup.periodDuration = .init(totalSeconds: $0 * 60)
              store.send(.updateRow(updated))
            }
          ), in: 1 ... 99)
          Picker("First centre pass", selection: Binding(get: { row.setup.firstCentrePass }, set: {
            var updated = row
            updated.setup.firstCentrePass = $0
            store.send(.updateRow(updated))
          })) {
            Text(store.state.team(row.firstKey)?.name ?? "First Team").tag(NewGameFeature.TeamSide.teamA)
            Text(store.state.team(row.secondKey)?.name ?? "Second Team").tag(NewGameFeature.TeamSide.teamB)
          }
          Text(row.setup.timing.summary).font(.footnote).foregroundStyle(.secondary)
        }
        Section("Source") { Text(row.source).font(.footnote).textSelection(.enabled) }
      }
      .navigationTitle("Edit Game")
      .disabled(store.isSaving)
    }
  }

  private func textBinding(_ row: BulkGamesFeature.Row, _ keyPath: WritableKeyPath<NewGameFeature.State, String>) -> Binding<String> {
    Binding(get: { row.setup[keyPath: keyPath] }, set: {
      var updated = row
      updated.setup[keyPath: keyPath] = $0
      store.send(.updateRow(updated))
    })
  }
}

package struct BulkTeamEditor: View {
  let store: StoreOf<BulkGamesFeature>
  let teamKey: String?
  let rowID: Game.ID
  let side: FixtureTeamReview.Side
  let title: String
  package var body: some View {
    Section(title) {
      if let key = teamKey, let entry = store.review?.entries.first(where: { $0.id == key }) {
        Text("Parsed: \(entry.name)").font(.footnote).foregroundStyle(.secondary)
        Menu {
          Button("Create New Team") { store.send(.selectTeam(key, .proposed)) }
          ForEach(store.savedTeams) { team in
            Button(team.name) { store.send(.selectTeam(key, .existing(team.id))) }
          }
        } label: {
          LabeledContent("Team", value: store.state.team(key)?.name ?? "Choose a team")
        }
        if entry.selection == .proposed {
          TextField("New team name", text: Binding(
            get: { store.proposals[key]?.name ?? "" },
            set: { store.send(.renameTeam(key, $0)) }
          ))
          Text("New team · Shared by every game with this parsed name")
            .font(.caption).foregroundStyle(.secondary)
        } else if entry.selection == nil {
          Text("Choose a saved team or confirm a new team.")
            .font(.caption).foregroundStyle(.orange)
          ForEach(entry.resolution.candidates, id: \.team.id) { candidate in
            Button("Use \(candidate.team.name)") { store.send(.selectTeam(key, .existing(candidate.team.id))) }
          }
        } else {
          Text("Saved team").font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup("Correct Parsed Name") {
          BulkParsedTeamEditor(store: store, rowID: rowID, side: side)
        }
      } else {
        BulkParsedTeamEditor(store: store, rowID: rowID, side: side)
      }
    }
  }
}

#Preview("Bulk entry") {
  let _ = try! prepareDependencies {
    try $0.bootstrapDatabase()
    $0.clipboard = .constant("""
    League name : Netball - Mixed (Clapham (Lambeth Academy) - Tues - Rec)

    Tue 03/11/2026

    19:50  Coles Hot Chooks vs The lodgers
    Division 1 • Court 1
    19:10  Clapham Ballers vs Pole vaulters
    Division 1 • Court 1
    18:30  Buzz Ballers vs IMG & Friends
    Division 1 • Court 1
    18:30  One Team, One Dream vs Silence of the Lambeths
    Division 2 • Court 2
    19:10  Silence of the Lambeths vs Netball & Chill
    Division 2 • Court 2
    19:50  Benny and the Nets vs Mixed Bag
    Division 2 • Court 2
    """)
  }
  BulkGamesView(store: Store(initialState: BulkGamesFeature.State()) { BulkGamesFeature() })
}

private struct BulkParsedTeamEditor: View {
  let store: StoreOf<BulkGamesFeature>
  let rowID: Game.ID
  let side: FixtureTeamReview.Side
  @State private var name = ""
  var body: some View {
    Text("Enter a team name to match or create.").foregroundStyle(.orange)
    TextField("Team name", text: $name)
    Button("Use Team Name") { store.send(.changeParsedTeam(rowID, side, name)) }
      .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }
}
