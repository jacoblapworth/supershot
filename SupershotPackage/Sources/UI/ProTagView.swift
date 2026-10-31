import SwiftUI

//
//  ProTagView.swift
//  Supershot
//
//  Created by J on 08/10/2026.
//

package struct ProTagView: View {
  package enum Variant {
    case primary
    case secondary
  }

  package var variant: Variant = .primary

  package var body: some View {
    switch variant {
    case .primary:
      Text("Pro")
        .fontWeight(.semibold)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .foregroundStyle(.white)
        .background(.purple, in: RoundedRectangle(cornerRadius: 4))
    case .secondary:
      Text("Pro")
        .fontWeight(.semibold)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .foregroundStyle(.purple)
        .background {
          RoundedRectangle(cornerRadius: 4)
            .stroke(.purple, style: .init())
        }
    }
  }

  package init(variant: Variant = .primary) {
    self.variant = variant
  }
}

#Preview {
  VStack {
    ProTagView(variant: .primary)
    ProTagView(variant: .secondary)
  }
}
