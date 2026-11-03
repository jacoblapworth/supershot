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
      .navigationTitle(store.showsPreview ? "Review Games" : "Create Games with AI")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { store.send(.cancelButtonTapped) }
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
    .environment(\.timeZone, TimeZone(identifier: store.timeZoneID) ?? .current)
    .interactiveDismissDisabled(store.isSaving)
    #if os(macOS)
      .frame(minWidth: 560, idealWidth: 640, minHeight: 600)
    #endif
  }
}

private struct BulkGamesInput: View {
  @Bindable var store: StoreOf<BulkGamesFeature>
  var body: some View {
    Form {
      Section {
        TextEditor(text: $store.source)
          .frame(minHeight: 240)
          .accessibilityLabel("Game descriptions")
          .accessibilityIdentifier("bulkGames.source")
        PasteButton(payloadType: String.self) { strings in
          store.source = strings.joined(separator: "\n")
        }
      } header: {
        Text("Type or paste your fixtures")
      } footer: {
        Text("Include team names, dates, times, divisions and courts. Review everything before saving. Up to 12 games per batch.")
      }
      Section {
        DatePicker("Date for time-only fixtures", selection: $store.sharedDate, displayedComponents: .date)
        Picker("Time zone", selection: $store.timeZoneID) {
          ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
            Text(identifier.replacingOccurrences(of: "_", with: " ")).tag(identifier)
          }
        }
      }
      if let error = store.errorMessage {
        Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("bulkGames.error") }
      }
      Section {
        Button {
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
    }
    .disabled(store.isParsing)
  }
}

private struct BulkGamesPreview: View {
  @Bindable var store: StoreOf<BulkGamesFeature>
  var body: some View {
    List {
      Section {
        Text("Check each game, then save the selected games. Team choices apply wherever that name appears.")
          .foregroundStyle(.secondary)
        DatePicker("Shared date", selection: $store.sharedDate, displayedComponents: .date)
        Button("Apply Date to All Games") { store.send(.applySharedDate) }
        Text("Time zone: \(store.timeZoneID)").font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        DisclosureGroup("Original Text") {
          Text(store.parsedSource ?? "").font(.footnote).textSelection(.enabled)
        }
      }
      Section("\(store.rows.count) games") {
        ForEach(store.rows) { row in
          BulkGamesPreviewRow(store: store, row: row)
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
          Text("Select games and resolve the highlighted details to save.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Button {
          store.send(.saveButtonTapped)
        } label: {
          HStack {
            if store.isSaving {
              ProgressView()
            }
            Text(store.isSaving ? "Saving…" : "Save All (\(store.selectedRows.count))")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!store.canSave)
        .accessibilityIdentifier("bulkGames.saveAll")
        Text("\(store.newTeamCount) new teams · Clocks stay stopped")
          .font(.caption).foregroundStyle(.secondary)
      }
      .padding()
      .background(.bar)
    }
  }
}

private struct BulkGamesPreviewRow: View {
  let store: StoreOf<BulkGamesFeature>
  let row: BulkGamesFeature.Row
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Toggle("Include game", isOn: Binding(get: { row.isSelected }, set: {
          var updated = row
          updated.isSelected = $0
          store.send(.updateRow(updated))
        }))
        .toggleStyle(.button)
        .font(.caption)
        Spacer()
        if !row.setup.division.isEmpty {
          Text("Division \(row.setup.division)").font(.caption)
        }
        if !row.setup.court.isEmpty {
          Text("Court \(row.setup.court)").font(.caption)
        }
      }
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
      if store.rows.contains(where: {
        $0.id != row.id && $0.firstKey == row.firstKey && $0.secondKey == row.secondKey
          && $0.setup.scheduledAt == row.setup.scheduledAt
      }) {
        Label("Possible duplicate — check before saving", systemImage: "doc.on.doc")
          .font(.caption).foregroundStyle(.orange)
      }
    }
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
  }
}

private struct BulkGameEditor: View {
  let store: StoreOf<BulkGamesFeature>
  let rowID: Game.ID
  var body: some View {
    if let row = store.rows.first(where: { $0.id == rowID }) {
      Form {
        BulkTeamEditor(store: store, teamKey: row.firstKey, rowID: row.id, side: .first, title: "First Team")
        BulkTeamEditor(store: store, teamKey: row.secondKey, rowID: row.id, side: .second, title: "Second Team")
        Section("Schedule") {
          DatePicker("Date and time", selection: Binding(get: { row.setup.scheduledAt ?? store.sharedDate }, set: {
            var updated = row
            updated.setup.scheduledAt = $0
            updated.needsScheduleReview = false
            updated.needsTimeReview = false
            updated.notices = []
            store.send(.updateRow(updated))
          }))
          if row.needsScheduleReview {
            Button("Confirm Date and Time") {
              var updated = row
              updated.setup.scheduledAt = row.setup.scheduledAt ?? store.sharedDate
              updated.needsScheduleReview = false
              updated.needsTimeReview = false
              updated.notices = []
              store.send(.updateRow(updated))
            }
          }
          Text("Time zone: \(store.timeZoneID)").font(.footnote).foregroundStyle(.secondary)
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

private struct BulkTeamEditor: View {
  let store: StoreOf<BulkGamesFeature>
  let teamKey: String?
  let rowID: Game.ID
  let side: FixtureTeamReview.Side
  let title: String
  var body: some View {
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
