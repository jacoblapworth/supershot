import SwiftUI

/// Locks each touch to its initial direction so a scroll cannot become chart inspection.
struct ChartSelectionOverlay: View {
  var selectionChanged: (CGPoint?) -> Void
  @GestureState private var interaction = Interaction.idle

  var body: some View {
    Rectangle()
      .fill(.clear)
      .contentShape(Rectangle())
      .simultaneousGesture(
        DragGesture(minimumDistance: 10)
          .updating($interaction) { value, interaction, _ in
            interaction.update(value)
          }
      )
      .onChange(of: interaction) { selectionChanged(interaction.location) }
  }

  private enum Interaction: Equatable {
    case idle
    case horizontal(CGPoint)
    case vertical

    var location: CGPoint? {
      guard case .horizontal(let location) = self else { return nil }
      return location
    }

    mutating func update(_ value: DragGesture.Value) {
      switch self {
      case .idle:
        self = abs(value.translation.width) > abs(value.translation.height)
          ? .horizontal(value.location) : .vertical
      case .horizontal:
        self = .horizontal(value.location)
      case .vertical:
        break
      }
    }
  }
}
