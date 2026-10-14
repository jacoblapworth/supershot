//
//  ScoringButtonsView.swift
//  Supershot
//
//  Created by J on 13/10/2026.
//
//
//import SwiftUI
//
//struct ScoringButtonsView: View {
//
//  var body: some View {
//    ScrollView {
//      VStack(alignment: .leading, spacing: 12) {
//      
//          HStack(spacing: 16) {
//            goalButton(for: store.courtLayout.left)
//            goalButton(for: store.courtLayout.right)
//          }
//          .environment(\.layoutDirection, .leftToRight)
//      }
//      .padding()
//    }
//    .scrollDisabled(true)
//    .buttonSizing(.flexible)
//    .buttonStyle(.glassProminent)
//    .presentationDetents(store.detents, selection: $store.presentationDetent)
//    .presentationBackgroundInteraction(.enabled)
//    .presentationBackground(alignment: .topLeading) {}
//    .interactiveDismissDisabled()
//    .presentationContentInteraction(.resizes)
//    .presentationDragIndicator(.hidden)
//#if os(iOS)
//    .presentationPlacement(.leading)
//  }
//  
//  
//  private func goalButton(for courtTeam: ScoringFeature.CourtTeam) -> some View {
//    Button(action: { store.send(.goalButtonTapped(courtTeam.id)) }) {
//      Label("Goal", systemImage: "plus")
//        .padding(24)
//    }
//    .tint(courtTeam.team.bibColor)
//    .accessibilityLabel("Goal for \(courtTeam.team.name)")
//    .font(.title2.bold())
//    .labelStyle(.iconOnly)
//  }
//}
