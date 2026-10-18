import SharedModels
import SwiftUI

#if os(iOS)
  nonisolated extension GameActivityAttributes {
    public var teamAColor: Color { Color(hex: teamAColorHex) }
    public var teamBColor: Color { Color(hex: teamBColorHex) }
  }
#endif
