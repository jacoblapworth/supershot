import SwiftUI

/// A dark, ambient blend with colours anchored to the physical sides of the court.
/// Place behind content using a dark colour scheme; this view fills its proposed size.
struct TeamColorBackground: View {
  var leftColor: Color
  var rightColor: Color

  @Environment(\.self) private var environment
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let left = TeamColorTreatment(color: leftColor, environment: environment).background
    let right = TeamColorTreatment(color: rightColor, environment: environment).background
    let middle = left.mix(with: right, by: 0.5, in: .device)

    TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || scenePhase != .active)) { context in
      // A full cycle takes about 75 seconds, with only a small change in the blend.
      let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 12
      let centreX = Float(0.5 + 0.035 * sin(phase))
      let centreY = Float(0.48 + 0.035 * cos(phase))

      MeshGradient(
        width: 3,
        height: 3,
        points: [
          [0, 0], [0.5, 0], [1, 0],
          [0, centreY], [centreX, centreY], [1, centreY],
          [0, 1], [0.5, 1], [1, 1]
        ],
        colors: [
          left, middle, right,
          left.mix(with: .black, by: 0.2, in: .device),
          middle.mix(with: .black, by: 0.3, in: .device),
          right.mix(with: .black, by: 0.2, in: .device),
          left.mix(with: .black, by: 0.75, in: .device),
          middle.mix(with: .black, by: 0.85, in: .device),
          right.mix(with: .black, by: 0.75, in: .device)
        ],
        smoothsColors: true,
        colorSpace: .device
      )
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

#Preview("Red and blue") {
  TeamColorBackground(leftColor: .red, rightColor: .blue)
    .ignoresSafeArea()
}

#Preview("White and yellow") {
  TeamColorBackground(leftColor: .white, rightColor: .yellow)
    .ignoresSafeArea()
}

#Preview("Black and purple") {
  TeamColorBackground(leftColor: .black, rightColor: .purple)
    .ignoresSafeArea()
}
