import SwiftUI

package struct CentrePassButton: View {
  package var color: Color
  package var isSelected: Bool
  package var name: String
  package var action: () -> Void

  package init(color: Color, isSelected: Bool, name: String, action: @escaping () -> Void) {
    self.color = color
    self.isSelected = isSelected
    self.name = name
    self.action = action
  }

  package var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        Text(name)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 8)
      .foregroundStyle(Color.primary)
      .background(
        isSelected ? color.opacity(0.2) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(
            isSelected ? color : Color.secondary.opacity(0.4),
            lineWidth: isSelected ? 2 : 1
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(name) centre pass")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
