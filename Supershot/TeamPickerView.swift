//
//  TeamPickerView.swift
//  Supershot
//
//  Created by J on 13/08/2026.
//

import ComposableArchitecture
import SwiftUI

struct TeamPickerView: View {
  @Bindable var store: StoreOf<TeamSlotFeature>
  var teams: [Team]
  var unavailableTeamID: Team.ID?
  
  var body: some View {
    List {
      Section {
        if teams.isEmpty {
          ContentUnavailableView(
            "No saved teams",
            systemImage: "person.2",
            description: Text("Create your first reusable team.")
          )
        } else if filteredTeams.isEmpty {
          ContentUnavailableView.search(text: $store.searchText)
        } else {
          ForEach(filteredTeams) { team in
            TeamSelectionRow(
              team: team,
              isUnavailable: team.id == unavailableTeamID,
              selected: { store.send(.existingTeamSelected(team)) }
            )
          }
        }
      }
      
      Section {
        Button(action: { store.send(.createTeamButtonTapped) }) {
          Label("Create new team", systemImage: "plus.circle.fill")
        }
      }
    }
    .searchable(text: $store.searchText, prompt: "Search teams")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel, action: { store.send(.cancelButtonTapped) })
      }
    }
  }
  
  private var filteredTeams: [Team] {
    let query = Team.trimmedName(store.searchText)
    guard !query.isEmpty else { return teams }
    return teams.filter {
      $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}

private struct TeamSelectionRow: View {
  var team: Team
  var isUnavailable: Bool
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
        if isUnavailable {
          Text("Already selected")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
      }
    }
    .disabled(isUnavailable)
    .accessibilityHint(isUnavailable ? "Already selected on the other side" : "")
  }
}

#Preview {
  Text("Background").sheet(isPresented: .constant(true)) {
    TeamPickerView(
      store: Store(initialState: .previewChoosing) { TeamSlotFeature() },
      teams: .previewTeams,
      unavailableTeamID: Team.previewSwifts.id,
    )
  }
}
