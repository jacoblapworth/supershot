import SwiftUI

extension View {
  package func setupCardStyle() -> some View {
    self
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}
