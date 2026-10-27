import ComposableArchitecture
import GameParser
import Styleguide
import SwiftUI

package struct DescribeGameView: View {
  @Bindable var store: StoreOf<DescribeGameFeature>

  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        TextField("Describe the game", text: $store.source, axis: .vertical)
          .lineLimit(1 ... 4)
          .textFieldStyle(.plain)
          .accessibilityHint("Teams and game details fill in automatically as you type.")
          .accessibilityIdentifier("gameSetup.description")

        if store.isParsing {
          ProgressView().accessibilityLabel("Finding game details")
        }

        if store.source.isEmpty {
          PasteButton(payloadType: String.self) { strings in
            store.send(.pasted(strings.joined(separator: "\n")))
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .accessibilityLabel("Paste game description")
        } else {
          Button {
            store.send(.clearButtonTapped)
          } label: {
            Label("Clear", systemImage: "xmark.circle.fill")
              .labelStyle(.iconOnly)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear description and populated game details")
          .accessibilityIdentifier("gameSetup.clearDescription")
        }
      }
      .setupCardStyle()

      if !store.source.isEmpty {
        if let error = store.errorMessage {
          Text(error).font(.footnote).foregroundStyle(.red)
            .accessibilityLabel("Error: \(error)")
        }
        ForEach(store.metadataNotices, id: \.self) { notice in
          Text(notice).font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .task { store.send(.task) }
  }
}
