import SharedModels
import SwiftUI

#if os(iOS)
  public nonisolated extension GameActivityAttributes {
    var teamAColor: Color {
      Color(hex: teamAColorHex)
    }

    var teamBColor: Color {
      Color(hex: teamBColorHex)
    }
  }
#endif
