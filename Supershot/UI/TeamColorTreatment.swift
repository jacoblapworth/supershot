import SwiftUI

/// Darkens arbitrary team colours for use behind light text while retaining their hue.
struct TeamColorTreatment {
  let background: Color

  init(color: Color, environment: EnvironmentValues) {
    self.init(resolvedColor: color.resolve(in: environment), contrast: environment.colorSchemeContrast)
  }

  init(resolvedColor resolved: Color.Resolved, contrast: ColorSchemeContrast) {
    let components = [resolved.red, resolved.green, resolved.blue].map {
      let value = Double(min(max($0, 0), 1))
      return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let luminance = components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    let maximumBackgroundLuminance = contrast == .increased ? 0.03 : 0.055
    let backgroundScale = luminance > maximumBackgroundLuminance
      ? maximumBackgroundLuminance / luminance : 1

    background = Color(
      .sRGBLinear,
      red: components[0] * backgroundScale,
      green: components[1] * backgroundScale,
      blue: components[2] * backgroundScale
    )
  }
}
