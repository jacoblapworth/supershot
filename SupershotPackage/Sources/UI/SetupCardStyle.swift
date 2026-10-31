import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

package extension Color {
  static var setupBackground: Color {
    #if os(iOS)
      Color(uiColor: .systemGroupedBackground)
    #else
      Color(nsColor: .windowBackgroundColor)
    #endif
  }
}

package extension EnvironmentValues {
  @Entry var usesNativeSetupRows = false
}

package extension View {
  func setupCardStyle() -> some View {
    modifier(SetupCardModifier())
  }
}

private struct SetupCardModifier: ViewModifier {
  @Environment(\.usesNativeSetupRows) private var usesNativeRows

  func body(content: Content) -> some View {
    content
      .padding(usesNativeRows ? 0 : 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 16)
          .fill(usesNativeRows ? AnyShapeStyle(.clear) : AnyShapeStyle(.thinMaterial))
      }
  }
}

#Preview("Standalone setup card") {
  Label("Quarter length: 15 minutes", systemImage: "timer")
    .setupCardStyle()
    .padding()
    .background(Color.setupBackground)
}

#Preview("Native setup row") {
  List {
    Label("Quarter length: 15 minutes", systemImage: "timer")
      .setupCardStyle()
  }
  .environment(\.usesNativeSetupRows, true)
}
