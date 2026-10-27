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

  static var setupContainer: Color {
    #if os(iOS)
      Color(uiColor: .secondarySystemGroupedBackground)
    #else
      Color(nsColor: .controlBackgroundColor)
    #endif
  }
}

package extension EnvironmentValues {
  @Entry var usesGroupedSetupContainers = false
}

package extension View {
  func setupCardStyle() -> some View {
    modifier(SetupCardModifier())
  }
}

private struct SetupCardModifier: ViewModifier {
  @Environment(\.usesGroupedSetupContainers) private var grouped

  func body(content: Content) -> some View {
    content
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: grouped ? 24 : 16)
          .fill(grouped ? AnyShapeStyle(Color.setupContainer) : AnyShapeStyle(.thinMaterial))
      }
  }
}
