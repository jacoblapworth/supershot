import SwiftUI
import Testing

@testable import Supershot

extension SupershotTestSuite {
  struct TeamColorTreatmentTests {
    @Test(arguments: ["#FFFFFF", "#FFFF00", "#000000", "#FF0000", "#0000FF", "#808080", "#00FF00"])
    func arbitraryTeamColorsKeepWhiteTextReadable(hex: String) {
      let environment = EnvironmentValues()
      let treatment = TeamColorTreatment(color: Color(hex: hex), environment: environment)
      let background = luminance(treatment.background, in: environment)

      #expect(background <= 0.0551)
      #expect(1.05 / (background + 0.05) > 9.9)
    }

    @Test
    func increasedContrastDarkensTheBackground() {
      let environment = EnvironmentValues()
      let treatment = TeamColorTreatment(
        resolvedColor: Color.yellow.resolve(in: environment),
        contrast: .increased
      )
      #expect(luminance(treatment.background, in: environment) <= 0.0301)
    }

    @Test
    func darkeningPreservesTeamHueInLinearColorSpace() {
      let environment = EnvironmentValues()
      let source = Color(.sRGBLinear, red: 0.8, green: 0.4, blue: 0.2)
      let treatment = TeamColorTreatment(color: source, environment: environment)
      let resolved = treatment.background.resolve(in: environment)
      #expect(abs(linear(resolved.red) / linear(resolved.green) - 2) < 0.001)
      #expect(abs(linear(resolved.green) / linear(resolved.blue) - 2) < 0.001)
    }

    private func luminance(_ color: Color, in environment: EnvironmentValues) -> Double {
      let resolved = color.resolve(in: environment)
      return linear(resolved.red) * 0.2126
        + linear(resolved.green) * 0.7152
        + linear(resolved.blue) * 0.0722
    }

    private func linear(_ component: Float) -> Double {
      let value = Double(component)
      return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
  }
}
