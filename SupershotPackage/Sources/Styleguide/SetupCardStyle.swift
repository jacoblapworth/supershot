import SwiftUI

package extension View {
  func setupCardStyle() -> some View {
    padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}
