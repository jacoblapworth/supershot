//
//  TeamPickerView.swift
//  Supershot
//
//  Created by J on 13/08/2026.
//

import ComposableArchitecture
import SwiftUI
import SQLiteData

struct TeamPickerView: View {
  @Bindable var store: StoreOf<TeamPickerFeature>
  
  var body: some View {
    List {
      Section {
        if store.isLoadingTeams {
          ProgressView("Loading saved teams…")
        } else if store.availableTeams.isEmpty {
          ContentUnavailableView(
            "No saved teams",
            systemImage: "person.2",
            description: Text("Create a team.")
          )
        } else {
          ForEach(store.filteredTeams) { team in
            TeamSelectionRow(
              team: team,
              selected: { store.send(.teamSelected(team)) }
            )
          }
        }
      }
      
      Section {
        Button { store.send(.createTeamButtonTapped) } label: {
          Label("Create new team", systemImage: "plus.circle.fill")
        }
      }
      
      if let errorMessage = store.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .overlay {
      if store.filteredTeams.isEmpty {
        ContentUnavailableView {
          Label("No matching teams", systemImage: "magnifyingglass")
        } description: {
          Text("Create a team named “\(Team.trimmedName(store.searchText))”.")
        } actions: {
          Button("Create “\(Team.trimmedName(store.searchText))”", systemImage: "plus.circle.fill") {
            store.send(.createTeamButtonTapped)
          }
          .buttonBorderShape(.roundedRectangle(radius: 12))
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .searchable(text: $store.searchText, prompt: "Search teams")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel) {
          store.send(.cancelButtonTapped)
        }
      }
    }
#if os(iOS)
    .toolbar(content: {
      DefaultToolbarItem(kind: .search, placement: .bottomBar)
      ToolbarSpacer(.flexible, placement: .bottomBar)
      ToolbarItem(placement: .bottomBar) {
        Button { store.send(.createTeamButtonTapped) } label: {
          Label("Create", systemImage: "plus.circle.fill")
        }
      }
    })
#else
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { store.send(.createTeamButtonTapped) } label: {
          Label("Create", systemImage: "plus.circle.fill")
        }
      }
    }
#endif
    .sheet(item: $store.scope(state: \.editor, action: \.editor)) { editorStore in
      NavigationStack {
        TeamEditorView(store: editorStore)
      }
    }
    .task { store.send(.task) }
  }
}

private struct TeamSelectionRow: View {
  var team: Team
  var selected: () -> Void
  
  var body: some View {
    Button(action: selected) {
      HStack(spacing: 12) {
        Circle()
          .fill(Color(teamHex: team.colorHex))
          .frame(width: 18, height: 18)
          .accessibilityHidden(true)
        Text(team.name)
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }.buttonStyle(.plain)
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  Text("Background")
    .sheet(isPresented: .constant(true)) {
      NavigationStack {
        TeamPickerView(
          store: Store(initialState: TeamPickerFeature.State()) {
            TeamPickerFeature()
          }
        )
      }
    }
}
