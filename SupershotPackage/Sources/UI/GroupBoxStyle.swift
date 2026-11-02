import SwiftUI

package struct StatGroupBoxStyle: GroupBoxStyle {
  package func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .center) {
      configuration.label
        .foregroundStyle(.secondary)
      configuration.content
        .font(.title2)
    }
    .padding(8)
    .frame(minWidth: 0, maxWidth: .infinity)
    .background(
      backgroundColor,
      in: RoundedRectangle(cornerRadius: 8)
    )
  }

  private var backgroundColor: Color {
    #if os(iOS)
      Color(uiColor: .secondarySystemGroupedBackground)
    #else
      Color(nsColor: .controlBackgroundColor)
    #endif
  }
}

package extension GroupBoxStyle where Self == StatGroupBoxStyle {
  static var statGroupBoxStyle: StatGroupBoxStyle {
    .init()
  }
}

#Preview {
  GroupBox("Label") {
    Text(8, format: .number)
  }
  .groupBoxStyle(.statGroupBoxStyle)
}
