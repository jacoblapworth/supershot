import ComposableArchitecture
import SwiftUI

struct NewGameTeamsView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Matchup", systemImage: "person.2.fill")
        .font(.headline)

      HStack(spacing: 10) {
        TeamCard(
          isDisabled: store.rightTeam.mode.isInteracting || store.isSaving,
          store: store.scope(state: \.leftTeam, action: \.leftTeam)
        )

        Button {
          store.send(.swapTeamsButtonTapped)
        } label: {
          Image(systemName: "arrow.left.arrow.right")
            .font(.headline)
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .disabled(!store.canSwapTeams)
        .accessibilityLabel("Swap left and right teams")

        TeamCard(
          isDisabled: store.leftTeam.mode.isInteracting || store.isSaving,
          store: store.scope(state: \.rightTeam, action: \.rightTeam)
        )
      }

      if store.isLoadingTeams {
        HStack(spacing: 8) {
          ProgressView()
          Text("Loading saved teams…")
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
      }
    }
    .setupCardStyle()
  }
}

private struct TeamCard: View {
  var isDisabled: Bool
  @Bindable var store: StoreOf<TeamSlotFeature>

  var body: some View {
    VStack(spacing: 10) {
      if let draft = store.selectedDraft {
        Circle()
          .fill(Color(teamHex: draft.colorHex))
          .frame(width: 30, height: 30)
          .overlay {
            Circle().stroke(.white.opacity(0.8), lineWidth: 2)
          }
          .accessibilityHidden(true)

        Text(draft.trimmedName)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)

        if store.mode == .locked {
          HStack(spacing: 8) {
            Button("Change") {
              store.send(.changeTeamButtonTapped)
            }
            Button("Edit") {
              store.send(.editTeamButtonTapped)
            }
          }
          .font(.caption)
          .buttonStyle(.bordered)

          if store.selection?.hasSharedChanges == true {
            VStack(spacing: 6) {
              Label(
                "Updates history",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
              )
              .font(.caption2)
              .foregroundStyle(.orange)
              Button("Revert edits") {
                store.send(.revertChangesButtonTapped)
              }
              .font(.caption)
            }
          }
        } else {
          Text("Choosing…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Button {
          store.send(.cardTapped)
        } label: {
          VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
              .font(.title)
            Text(store.side.title)
              .font(.headline)
            Text("Tap to choose")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 150)
    .padding(10)
    .background(
      Color(teamHex: store.selectedDraft?.colorHex ?? store.side.defaultColorHex).opacity(0.09),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          store.mode.isInteracting
            ? Color(teamHex: store.selectedDraft?.colorHex ?? store.side.defaultColorHex)
            : Color.secondary.opacity(0.25),
          lineWidth: store.mode.isInteracting ? 2 : 1
        )
    }
    .disabled(isDisabled)
  }
}

#Preview("Empty matchup") {
  NewGameTeamsView(store: setupPreviewStore())
    .padding()
}

#Preview("Selected matchup") {
  NewGameTeamsView(store: setupPreviewStore(.previewReady))
    .padding()
}

#Preview("Loading matchup") {
  NewGameTeamsView(store: setupPreviewStore(.previewLoading))
    .padding()
}
