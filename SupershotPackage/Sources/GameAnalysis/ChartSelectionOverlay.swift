import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Rejects vertical drags before recognition so the parent scroll view can handle them.
struct ChartSelectionOverlay: View {
  var selectionChanged: (CGPoint?) -> Void
  #if !os(iOS)
    @GestureState private var interaction = Interaction.idle
  #endif

  var body: some View {
    Rectangle()
      .fill(.clear)
      .contentShape(Rectangle())
    #if os(iOS)
      .gesture(HorizontalChartPan(selectionChanged: selectionChanged))
    #else
      .simultaneousGesture(DragGesture(minimumDistance: 10)
        .updating($interaction) { value, interaction, _ in
          interaction.update(value)
        })
      .onChange(of: interaction) { selectionChanged(interaction.location) }
    #endif
  }

  #if !os(iOS)
    private enum Interaction: Equatable {
      case idle
      case horizontal(CGPoint)
      case vertical

      var location: CGPoint? {
        guard case let .horizontal(location) = self else { return nil }
        return location
      }

      mutating func update(_ value: DragGesture.Value) {
        switch self {
        case .idle:
          self =
            abs(value.translation.width) > abs(value.translation.height)
              ? .horizontal(value.location)
              : .vertical
        case .horizontal:
          self = .horizontal(value.location)
        case .vertical:
          break
        }
      }
    }
  #endif
}

#if os(iOS)
  private struct HorizontalChartPan: UIGestureRecognizerRepresentable {
    var selectionChanged: (CGPoint?) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
      Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
      let recognizer = UIPanGestureRecognizer()
      recognizer.maximumNumberOfTouches = 1
      recognizer.delegate = context.coordinator
      return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
      switch recognizer.state {
      case .began, .changed:
        selectionChanged(context.converter.localLocation)
      default:
        selectionChanged(nil)
      }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let translation = recognizer.translation(in: recognizer.view)
        return abs(translation.x) > abs(translation.y)
      }
    }
  }
#endif
