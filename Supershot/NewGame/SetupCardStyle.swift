import SwiftUI

extension View {
  func setupCardStyle() -> some View {
    self
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}
