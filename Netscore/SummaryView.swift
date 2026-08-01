import ComposableArchitecture
import SwiftUI

struct SummaryView: View {
  let store: StoreOf<SummaryFeature>

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "flag.checkered")
          .font(.system(size: 48, weight: .semibold))
          .foregroundStyle(.secondary)

        Text(store.resultTitle)
          .font(.largeTitle.bold())
          .multilineTextAlignment(.center)

        HStack(spacing: 16) {
          SummaryScore(name: store.teamAName, score: store.teamAScore)
          SummaryScore(name: store.teamBName, score: store.teamBScore)
        }

        Button {
          store.send(.newGameButtonTapped)
        } label: {
          Label("New game", systemImage: "plus.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
      .navigationTitle("Final score")
    }
  }
}

private struct SummaryScore: View {
  var name: String
  var score: Int

  var body: some View {
    VStack(spacing: 10) {
      Text(name)
        .font(.headline)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(minHeight: 44)

      Text("\(score)")
        .font(.system(size: 56, weight: .bold, design: .rounded))
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, minHeight: 140)
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}

#Preview {
  SummaryView(
    store: Store(
      initialState: SummaryFeature.State(
        endedAt: Date(),
        startedAt: Date(),
        teamAName: "Ravens",
        teamAScore: 42,
        teamBName: "Swifts",
        teamBScore: 39
      )
    ) {
      SummaryFeature()
    }
  )
}
