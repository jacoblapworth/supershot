import ComposableArchitecture
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SetupLocationView: View {
  @Environment(\.openURL) private var openURL
  let store: StoreOf<NewGameFeature>
  
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch store.location {
      case .idle:
        
        ContentUnavailableView {
          Label("Remember where you played", systemImage: "mappin.and.ellipse")
        } description: {
          Text("Add your current location to save the venue with this game.")
        } actions: {
          Button("Add location") { store.send(.locationButtonTapped) }
            .fontWeight(.medium)
            .buttonStyle(.glassProminent)
        }
      
      case .denied:
        Text("Allow location access to save where you played.")
          .foregroundStyle(.secondary)
#if os(iOS)
        Button("Open Settings") {
          openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
        .buttonStyle(.bordered)
#else
        Button("Open Settings") {
          openURL(URL(string: "x-apple.systempreferences:")!)
        }
        .buttonStyle(.bordered)
        Text("Allow location access for Supershot in Privacy & Security → Location Services.")
          .font(.caption).foregroundStyle(.secondary)
#endif
        
      case .restricted:
        Text("Location access is restricted on this device. You can start the game without a location.")
          .foregroundStyle(.secondary)
        
      case .requesting, .loading:
        HStack(spacing: 12) {
          ProgressView()
          Text(store.location == .requesting ? "Requesting access…" : "Finding your current location…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        
      case let .loaded(location):
        GameLocationMap(location: location)
        HStack {
          
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
          Spacer()
          Button("Refresh", systemImage: "arrow.clockwise") {
            store.send(.locationButtonTapped)
          }
          .labelStyle(.iconOnly)
          .font(.subheadline)
        }
        
      case .failed:
        VStack(alignment: .leading, spacing: 12) {
          Label("Couldn’t find your location. You can start the game without it.", systemImage: "location.slash")
            .foregroundStyle(.secondary)
          Button("Try again") { store.send(.locationButtonTapped) }
            .buttonStyle(.bordered)
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

#Preview("Loading") {
  var state = NewGameFeature.State.previewReady
  let _ = { state.location = .loading }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

#Preview("Idle") {
  var state = NewGameFeature.State.previewReady
  let _ = { state.location = .idle }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

#Preview("Unavailable") {
  var state = NewGameFeature.State()
  let _ = { state.location = .failed }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}
