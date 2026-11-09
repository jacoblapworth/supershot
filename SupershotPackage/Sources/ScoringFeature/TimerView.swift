import SwiftUI

/// Renders the feature's clock projection; game progression belongs to the toolbar.
package struct TimerView: View {
  package var state: TimerViewState
  package var onAction: (ScoringControlAction) -> Void

  package var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(state.title)
          .font(.footnote)
      }
      HStack {
        clockText
          .font(.system(size: 56, weight: .bold, design: .rounded))
          .monospacedDigit()
          .contentTransition(.numericText())
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        Spacer(minLength: 8)
        HStack(spacing: 8) {
          ForEach(state.controls.indices, id: \.self) { index in
            let control = state.controls[index]
            Button {
              onAction(control.action)
            } label: {
              ZStack {
                Label(control.title, systemImage: control.systemImage)
                  .opacity(control.availability == .pending ? 0 : 1)
                if control.availability == .pending {
                  ProgressView()
                }
              }
            }
            .accessibilityLabel(control.title)
            .labelStyle(.iconOnly)
            .font(.title2)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(control.availability != .enabled)
          }
        }
      }
      if state.waitingSince == nil {
        ProgressView(
          value: Double(state.elapsedSeconds),
          total: Double(max(state.durationSeconds, 1))
        )
        .animation(.linear, value: state.elapsedSeconds)
        .controlSize(.large)
        .accessibilityLabel("Quarter time elapsed")
      }
    }
    .foregroundStyle(.white)
    .padding()
    .background(.black, in: RoundedRectangle(cornerRadius: 24))
  }

  private var clockText: Text {
    if let waitingSince = state.waitingSince {
      Text(waitingSince, style: .timer)
    } else {
      Text(formattedTime)
    }
  }

  private var formattedTime: String {
    "\(state.remainingSeconds / 60):\(String(format: "%02d", state.remainingSeconds % 60))"
  }
}

#Preview("Timer states") {
  ScrollView {
    VStack {
      ForEach(ScoringPreviewScenario.allCases) { scenario in
        VStack(alignment: .leading) {
          Text(scenario.rawValue).font(.caption)
          TimerView(state: scenario.state.timerViewState, onAction: { _ in })
        }
      }
    }.padding()
  }.preferredColorScheme(.dark)
}
