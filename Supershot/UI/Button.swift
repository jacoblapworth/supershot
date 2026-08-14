//
//  Button.swift
//  Supershot
//
//  Created by J on 13/08/2026.
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
  private var cornerRadius: CGFloat = 12
  
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
      .bold()
      .frame(maxWidth: .infinity)
      .foregroundStyle(.white)
      .background(Color.accentColor)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(Color.secondary, lineWidth: 0.5)
      }
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(.smooth, value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
  static var myAppPrimaryButton: PrimaryButtonStyle { .init() }
}

#Preview {
  Button(action: {}) {
    Label("Label", systemImage: "plus.circle.fill")
  }
  .buttonStyle(.myAppPrimaryButton)
}
