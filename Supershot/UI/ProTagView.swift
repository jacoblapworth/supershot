//
//  ProTagView.swift
//  Supershot
//
//  Created by J on 08/10/2026.
//

import SwiftUI

struct ProTagView: View {
  
  enum Variant {
    case primary
    case secondary
  }
  
  var variant: Variant = .primary
  
  var body: some View {
    Group {
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
  }
}

#Preview {
  VStack {
    ProTagView(variant: .primary)
    ProTagView(variant: .secondary)
  }
}
