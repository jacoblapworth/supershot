import ComposableArchitecture
import Foundation
import LocationClient
import SharedModels
import SwiftUI

package struct SetupLocationPickerView: View {
  package let store: StoreOf<SetupLocationPickerFeature>

  package var body: some View {
    NavigationStack {
      List {
        if let currentLocation = store.currentLocation {
          Button {
            store.send(.currentLocationTapped)
          } label: {
            selectionLabel("Use current location", selected: store.selectedLocation == currentLocation)
          }
        }

        Section("Nearby places") {
          ForEach(store.places) { place in
            Button {
              store.send(.placeTapped(place.id))
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(place.location.pointOfInterestName ?? "")
                    .foregroundStyle(.primary)
                  Text(Measurement(value: place.distance, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .road))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if store.selectedLocation == place.location {
                  Image(systemName: "checkmark")
                    .accessibilityLabel("Selected")
                }
              }
            }
            .accessibilityAddTraits(store.selectedLocation == place.location ? .isSelected : [])
          }

          switch store.locationStatus {
          case .loading, .requesting:
            ProgressView("Finding your current location…")
          case .denied, .restricted, .idle:
            Text("Allow location access to find nearby places.")
              .foregroundStyle(.secondary)
          case .failed:
            Text("Couldn’t find your current location.")
            Button("Try again") { store.send(.retryButtonTapped) }
          case .loaded:
            switch store.status {
            case .loading:
              ProgressView("Finding nearby places…")
            case .failed:
              Text("Couldn’t load nearby places.")
              Button("Try again") { store.send(.retryButtonTapped) }
            case .loaded where store.places.isEmpty:
              Text("No nearby places found. You can use your current location.")
                .foregroundStyle(.secondary)
            case .idle, .loaded:
              EmptyView()
            }
          }
        }
      }
      .navigationTitle("Choose location")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { store.send(.closeButtonTapped) }
          }
        }
    }
    .presentationDetents([.medium, .large])
  }

  private func selectionLabel(_ title: LocalizedStringKey, selected: Bool) -> some View {
    HStack {
      Label(title, systemImage: "location")
      Spacer()
      if selected {
        Image(systemName: "checkmark")
          .accessibilityLabel("Selected")
      }
    }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
