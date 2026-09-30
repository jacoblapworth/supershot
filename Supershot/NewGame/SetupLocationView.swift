import ComposableArchitecture
import SwiftUI

struct SetupLocationView: View {
  let store: StoreOf<NewGameFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("Location", systemImage: "location.fill")
          .font(.headline)

        Spacer()

        if case .loaded = store.location {
          Button("Refresh", systemImage: "arrow.clockwise") {
            store.send(.locationButtonTapped)
          }
          .font(.subheadline)
        }
      }

      switch store.location {
      case .idle, .loading:
        HStack(spacing: 12) {
          ProgressView()
          Text("Finding your current location…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)

      case let .loaded(location):
        GameLocationMap(location: location)
        Label {
          if let pointOfInterestName = location.pointOfInterestName {
            Text(pointOfInterestName)
          } else {
            Text("Game location")
          }
        } icon: {
          Image(systemName: "mappin.and.ellipse")
        }
        .font(.subheadline.weight(.semibold))

      case let .unavailable(canRetry):
        VStack(alignment: .leading, spacing: 12) {
          Label(
            "A location won’t be saved with this game.",
            systemImage: "location.slash"
          )
          .foregroundStyle(.secondary)

          if canRetry {
            Button("Try again") {
              store.send(.locationButtonTapped)
            }
            .buttonStyle(.bordered)
          } else {
            Text("You can allow location access in Settings.")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
      }
    }
    .setupCardStyle()
  }
}

#Preview("Loaded") {
  var state = NewGameFeature.State.previewReady
  let _ = { state.location = .loaded(LocationClient.previewLocation) }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

#Preview("Unavailable") {
  var state = NewGameFeature.State()
  let _ = { state.location = .unavailable(canRetry: true) }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}
