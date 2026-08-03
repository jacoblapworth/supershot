import Dependencies
import SwiftUI

struct TeamsHomeView: View {
  var deleteTeamTapped: (Team.ID) -> Void
  var deletingTeamID: Team.ID?
  var newTeamTapped: () -> Void
  var teamTapped: (TeamListItem) -> Void
  var teams: [TeamListItem]

  var body: some View {
    List {
      if teams.isEmpty {
        ContentUnavailableView(
          "No teams yet",
          systemImage: "person.2",
          description: Text("Create a team to use in your next game.")
        )
        .listRowBackground(Color.clear)
      } else {
        ForEach(teams) { team in
          Button {
            teamTapped(team)
          } label: {
            TeamRow(team: team)
          }
          .buttonStyle(.plain)
          .disabled(deletingTeamID != nil)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              deleteTeamTapped(team.id)
            }
          }
        }
      }
    }
    .navigationTitle("Teams")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: newTeamTapped) {
          Label("New team", systemImage: "plus")
        }
        .disabled(deletingTeamID != nil)
      }
    }
  }
}

private struct TeamRow: View {
  var team: TeamListItem

  var body: some View {
    HStack(spacing: 14) {
      Circle()
        .fill(Color(teamHex: team.colorHex))
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)

      Text(team.name)
        .font(.headline)
        .foregroundStyle(.primary)

      Spacer(minLength: 12)

      Text(team.gameCount == 1 ? "1 game" : "\(team.gameCount) games")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

#Preview("Empty teams") {
  NavigationStack {
    TeamsHomeView(
      deleteTeamTapped: { _ in },
      deletingTeamID: nil,
      newTeamTapped: {},
      teamTapped: { _ in },
      teams: []
    )
  }
}

#Preview("Teams") {
  NavigationStack {
    TeamsHomeView(
      deleteTeamTapped: { _ in },
      deletingTeamID: nil,
      newTeamTapped: {},
      teamTapped: { _ in },
      teams: [
        TeamListItem(
          colorHex: TeamColorPalette.blue,
          gameCount: 4,
          id: UUID(1),
          name: "North London Ravens"
        ),
        TeamListItem(
          colorHex: TeamColorPalette.red,
          gameCount: 1,
          id: UUID(2),
          name: "Westminster Swifts"
        ),
      ]
    )
  }
}
