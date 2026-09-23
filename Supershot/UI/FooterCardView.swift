//
//  FooterCardView.swift
//  Supershot
//
//  Created by J on 09/09/2026.
//

import SwiftUI

struct FooterCardView: View {
    var body: some View {
      ZStack {
        VStack {
          Spacer()
//          HStack(spacing: 8) {
//            Button(action: {}) {
//              Label("Goal", systemImage: "plus.circle.fill")
//            }
//            Button(action: {}) {
//              Label("Goal", systemImage: "plus.circle.fill")
//            }
//          }
//          .buttonSizing(.flexible)
//          .buttonStyle(.myAppPrimaryButton)
//          .padding(8)
//          .frame(maxWidth: .infinity)
//          //        .background(content: {
//          //          ConcentricRectangle(
//          //            corners: .concentric,
//          //            isUniform: true)
//          //          .fill(.thinMaterial)
//          //        })
//          //        .cornerRadius(24)
//          //        .background(.thinMaterial)
//          .glassEffect(in:
//                        ConcentricRectangle(
//                          corners: .concentric,
//                          isUniform: true)
//          )
//          .padding(8)
          
//          ConcentricRectangle(
//            corners: .concentric,
//            isUniform: true
//          )
          VStack {
            
          }
           .containerShape(ContainerRelativeShape())
        }
      }
      .ignoresSafeArea()
    }
}

#Preview {
  NavigationView {
    FooterCardView()
  }.toolbar {
    ToolbarItemGroup(placement: .bottomBar) {
      HStack {
        Text("Test")
        Text("Test")
      }
      .background(in: .containerRelative)
    }
  }
}
