import SwiftUI
import UI

package struct ScoringToolbarView<Primary: View, Actions: View>: View {
  package var state: ScoringToolbarState
  package var onAction: (ScoringControlAction) -> Void
  package var onFrameChange: (CGRect) -> Void = { _ in }
  @ViewBuilder package var primary: (ScoringToolbarActions) -> Primary
  @ViewBuilder package var actions: (ScoringToolbarActions) -> Actions
  @State private var collapseRevision = 0

  package init(
    state: ScoringToolbarState,
    onAction: @escaping (ScoringControlAction) -> Void,
    onFrameChange: @escaping (CGRect) -> Void = { _ in },
    @ViewBuilder primary: @escaping (ScoringToolbarActions) -> Primary,
    @ViewBuilder actions: @escaping (ScoringToolbarActions) -> Actions
  ) {
    self.state = state
    self.onAction = onAction
    self.onFrameChange = onFrameChange
    self.primary = primary
    self.actions = actions
  }

  package var body: some View {
    #if os(iOS)
      ExpandableControlsSheet(
        reveal: state.sheetReveal,
        collapseTrigger: collapseRevision,
        onFrameChange: onFrameChange
      ) {
        ScoringButtonsView(
          courtLayout: state.courtLayout,
          onAction: onAction
        )
        .disabled(!state.canScore)
      } primary: {
        primary(ScoringToolbarActions(
          primaryControl: state.sheetPrimaryControl,
          controls: state.additionalControls,
          onAction: onAction
        ))
      } additional: {
        actions(ScoringToolbarActions(
          primaryControl: state.sheetPrimaryControl,
          controls: state.additionalControls,
          onAction: onAction
        ))
      }
      .presentationPlacement(.leading)
      .onChange(of: state) { previous, current in
        if current.shouldCollapse(after: previous) {
          collapseRevision += 1
        }
      }
    #else
      // Keep the existing macOS bottom-bar layout.
      VStack(spacing: 16) {
        switch state.content {
        case .none:
          EmptyView()
        case let .primary(control):
          ScoringToolbarButton(control: control, isPrimary: true, onAction: onAction)
            .buttonStyle(.glassProminent)
            .tint(.green)
            .fontWeight(.semibold)
        case let .confirmation(confirmation):
          LastCentrePassBanner(availability: confirmation.availability) {
            onAction(.confirmCentrePass($0))
          }
          .id(confirmation.period)
          .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 32))
        }
        ScoringButtonsView(courtLayout: state.courtLayout, onAction: onAction)
          .disabled(!state.canScore)
      }
      .padding()
      .frame(maxWidth: 420)
    #endif
  }
}

package extension ScoringToolbarView where Primary == ScoringPrimaryControl {
  init(
    state: ScoringToolbarState,
    onAction: @escaping (ScoringControlAction) -> Void,
    onFrameChange: @escaping (CGRect) -> Void = { _ in },
    @ViewBuilder actions: @escaping (ScoringToolbarActions) -> Actions
  ) {
    self.init(
      state: state,
      onAction: onAction,
      onFrameChange: onFrameChange,
      primary: { ScoringPrimaryControl(actions: $0) },
      actions: actions
    )
  }
}

package extension ScoringToolbarView where Primary == ScoringPrimaryControl, Actions == ScoringAdditionalControls {
  init(
    state: ScoringToolbarState,
    onAction: @escaping (ScoringControlAction) -> Void,
    onFrameChange: @escaping (CGRect) -> Void = { _ in }
  ) {
    self.init(state: state, onAction: onAction, onFrameChange: onFrameChange) {
      ScoringAdditionalControls(actions: $0)
    }
  }
}

/// Supplies state-aware buttons without choosing their layout or visual style.
package struct ScoringToolbarActions {
  let primaryControl: ScoringControl?
  let controls: [ScoringControl]
  var onAction: (ScoringControlAction) -> Void

  package func contains(_ action: ScoringControlAction) -> Bool {
    primaryControl?.action == action || controls.contains { $0.action == action }
  }

  @ViewBuilder
  package var primaryButton: some View {
    if let control = primaryControl {
      ScoringToolbarButton(control: control, isPrimary: true, onAction: onAction)
    }
  }

  private func control(for action: ScoringControlAction) -> ScoringControl? {
    if primaryControl?.action == action {
      return primaryControl
    }
    return controls.first { $0.action == action }
  }

  @ViewBuilder
  package func button(_ action: ScoringControlAction) -> some View {
    if let control = control(for: action) {
      ScoringToolbarButton(control: control, isPrimary: primaryControl?.action == action, onAction: onAction)
    }
  }

  @ViewBuilder
  package func button(
    _ action: ScoringControlAction,
    @ViewBuilder label: () -> some View
  ) -> some View {
    if let control = control(for: action) {
      ScoringActionButton(
        control: control,
        identifier: primaryControl?.action == action ? "scoring.primaryAction" : "scoring.control.\(String(describing: action))",
        onAction: onAction,
        label: label()
      )
    }
  }
}

package struct ScoringPrimaryControl: View {
  let actions: ScoringToolbarActions

  package var body: some View {
    actions.primaryButton
      .buttonStyle(.glassProminent)
      .tint(.green)
      .fontWeight(.semibold)
  }
}

/// Edit these ordinary SwiftUI rows to change the default action design.
/// Callers can also supply their own actions builder to ScoringToolbarView.
package struct ScoringAdditionalControls: View {
  let actions: ScoringToolbarActions

  package var body: some View {
    VStack(spacing: 12) {
      if actions.contains(.pause) || actions.contains(.skipBreak) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            actions.button(.pause)
            actions.button(.skipBreak)
          }
          VStack(spacing: 12) {
            actions.button(.pause)
            actions.button(.skipBreak)
          }
        }
      }
      if actions.contains(.editTime) || actions.contains(.endQuarter) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            actions.button(.editTime) {
              Label("Edit time", systemImage: "pencil")
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            actions.button(.endQuarter)
          }
          VStack(spacing: 12) {
            actions.button(.editTime)
            actions.button(.endQuarter)
          }
        }
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          actions.button(.changeCentrePass) {
            Label("Centre pass", systemImage: "arrow.left.circle.fill")
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          actions.button(.swapSides)
        }
        VStack(spacing: 12) {
          actions.button(.changeCentrePass)
          actions.button(.swapSides)
        }
      }
    }
    .buttonStyle(.glass)
  }
}

private struct ScoringToolbarButton: View {
  let control: ScoringControl
  let isPrimary: Bool
  var onAction: (ScoringControlAction) -> Void

  var body: some View {
    ScoringActionButton(
      control: control,
      identifier: isPrimary ? "scoring.primaryAction" : "scoring.control.\(String(describing: control.action))",
      onAction: onAction,
      label: Label(control.title, systemImage: control.systemImage)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44)
    )
  }
}

private struct ScoringActionButton<Label: View>: View {
  let control: ScoringControl
  let identifier: String
  var onAction: (ScoringControlAction) -> Void
  var label: Label

  var body: some View {
    Button { onAction(control.action) } label: {
      ZStack {
        label.opacity(control.availability == .pending ? 0 : 1)
        if control.availability == .pending {
          ProgressView()
        }
      }
    }
    .disabled(control.availability != .enabled)
    .accessibilityLabel(control.title)
    .accessibilityIdentifier(identifier)
  }
}

#if os(iOS)
  private struct ScoringToolbarSheetPreview: View {
    @State private var scenario = ScoringPreviewScenario.running

    var body: some View {
      NavigationStack {
        Form {
          Picker("Game state", selection: $scenario) {
            ForEach(ScoringPreviewScenario.allCases) { Text($0.rawValue).tag($0) }
          }
        }
        .navigationTitle("Scoring controls")
        .sheet(isPresented: .constant(true)) {
          ScoringToolbarView(state: scenario.state.scoringToolbarState, onAction: { _ in })
        }
      }
      .preferredColorScheme(.dark)
    }
  }

  #Preview("Adaptive scoring sheet") {
    ScoringToolbarSheetPreview()
  }

  #Preview("Custom action design") {
    Color.clear
      .sheet(isPresented: .constant(true)) {
        ScoringToolbarView(
          state: ScoringPreviewScenario.runningBreak.state.scoringToolbarState,
          onAction: { _ in }
        ) { actions in
          VStack(spacing: 20) {
            HStack(spacing: 12) {
              actions.button(.pause).tint(.orange)
              actions.button(.skipBreak).tint(.blue)
            }
            .buttonStyle(.glassProminent)

            HStack(spacing: 24) {
              actions.button(.changeCentrePass) {
                Label("Centre pass", systemImage: "arrow.left.circle.fill")
              }
              actions.button(.swapSides)
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .controlSize(.large)
          }
        }
      }
  }

  #Preview("Custom primary row") {
    Color.clear
      .sheet(isPresented: .constant(true)) {
        ScoringToolbarView(
          state: ScoringPreviewScenario.pausedBreak.state.scoringToolbarState,
          onAction: { _ in }
        ) { actions in
          HStack(spacing: 12) {
            actions.primaryButton.tint(.green)
            actions.button(.skipBreak).tint(.orange)
          }
          .buttonStyle(.glassProminent)
        } actions: { actions in
          HStack(spacing: 12) {
            actions.button(.changeCentrePass)
            actions.button(.swapSides)
          }
          .buttonStyle(.glass)
        }
      }
  }

  #Preview("Adaptive sheet • large text") {
    ScoringToolbarSheetPreview()
      .environment(\.dynamicTypeSize, .accessibility3)
  }
#else
  #Preview("Toolbar states") {
    ScrollView {
      VStack(spacing: 24) {
        ForEach(ScoringPreviewScenario.allCases) { scenario in
          VStack {
            Text(scenario.rawValue).font(.caption)
            ScoringToolbarView(state: scenario.state.scoringToolbarState, onAction: { _ in })
          }
        }
      }
    }.preferredColorScheme(.dark)
  }

  #Preview("Toolbar • large text", traits: .fixedLayout(width: 390, height: 844)) {
    VStack {
      Spacer()
      ScoringToolbarView(
        state: ScoringPreviewScenario.confirmation.state.scoringToolbarState,
        onAction: { _ in }
      )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
  }

  #Preview("Toolbar • landscape", traits: .fixedLayout(width: 844, height: 390)) {
    VStack {
      Spacer()
      ScoringToolbarView(
        state: ScoringPreviewScenario.confirmation.state.scoringToolbarState,
        onAction: { _ in }
      )
    }.preferredColorScheme(.dark)
  }

#endif
