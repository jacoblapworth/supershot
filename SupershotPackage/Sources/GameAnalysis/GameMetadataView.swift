//
//  GameMetadataView.swift
//  SupershotPackage
//
//  Created by J on 11/11/2026.
//

import SwiftUI
import Database
import PreviewSupport
import UI

struct GameMetadataView: View {
  var detail: CompletedGameDetail
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let court = detail.court {
        LabeledContent {
          Text(court)
        } label: {
          Label("Court", systemImage: "sportscourt")
        }
      }
      
      LabeledContent {
        Text(detail.startedAt.formatted(date: .abbreviated, time: .shortened))
      } label: {
        Label("Started", systemImage: "calendar")
      }
      
      LabeledContent {
        Text(detail.timingSummary)
          .multilineTextAlignment(.trailing)
      } label: {
        Label("Timing", systemImage: "clock")
      }
    }
    .labeledContentStyle(.inline)
    .labelReservedIconWidth(20)
    .font(.footnote)
  }
}

#Preview {
  GroupBox {
    GameMetadataView(detail: .previewCompleted)
  }
}
