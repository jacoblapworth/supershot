import AlarmClient
import AppSettings
import AppUI
import ComposableArchitecture
import Database
import Dependencies
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import SQLiteData
import SubscriptionClient
import SwiftUI
import UI

package struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Fetch private var analysisResponse: GameAnalysisRequest.Value
  @State private var selectedAnalysis = GameAnalysisTab.playByPlay
  @State private var viewportHeight: CGFloat = 0
  @State private var controlsHeight: CGFloat = 176
  @State private var isScoreboardAboveViewport = false
  @Bindable package var store: StoreOf<ScoringFeature>
  package let proAccess: SubscriptionEntitlement
  package let isPresentingPaywall: Bool

  package init(
    store: StoreOf<ScoringFeature>,
    proAccess: SubscriptionEntitlement = .unknown,
    isPresentingPaywall: Bool = false
  ) {
    self.isPresentingPaywall = isPresentingPaywall
    self.proAccess = proAccess
    self.store = store
    _analysisResponse = Fetch(
      wrappedValue: GameAnalysisRequest.Value(
        analysis: GameAnalysis(
          goalTimeline: .empty(through: store.period),
          periods: store.periods,
          teamABibColor: store.teamA.bibColor,
          teamAName: store.teamA.name,
          teamBBibColor: store.teamB.bibColor,
          teamBName: store.teamB.name
        )
      ),
      GameAnalysisRequest(gameID: store.gameID),
      animation: .default
    )
  }

  package var body: some View {
    ScrollViewReader { scrollProxy in
      ScrollView {
        LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
          VStack {
            TimerView(state: store.timerViewState) { store.send(.controlTapped($0)) }

            ScoreboardView(
              courtLayout: store.courtLayout
            )
            .onGeometryChange(for: Bool.self) { geometry in
              geometry.frame(in: .named("scoringViewport")).maxY <= 0
            } action: { isAboveViewport in
              isScoreboardAboveViewport = isAboveViewport
            }
          }
          .padding(.top)
          if store.scheduledAt != nil || store.court != nil {
            VStack(spacing: 8) {
              if let scheduledAt = store.scheduledAt {
                LabeledContent("Scheduled") {
                  Text(scheduledAt.formatted(date: .abbreviated, time: .shortened))
                }
              }
              if let startedAt = store.startedAt {
                LabeledContent("Started") {
                  Text(startedAt.formatted(date: .abbreviated, time: .shortened))
                }
              }
              if let court = store.court {
                LabeledContent("Court", value: court)
              }
            }
            .font(.subheadline)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
          }
          #if os(macOS)
            AlarmPermissionCard(
              store: store.scope(state: \.alarms, action: \.alarms),
              proAccess: proAccess, hidesWhenAuthorized: true
            )
          #endif
          Section {
            GameAnalysisContentView(
              analysis: analysisResponse.analysis,
              selection: selectedAnalysis,
              teamAOnLeft: store.courtLayout.left.team.id == store.teamA.id
            )
            .frame(minHeight: max(viewportHeight - 68, 0), alignment: .top)
          } header: {
            GameAnalysisControl(selection: $selectedAnalysis) {
              withAnimation(nil) {
                scrollProxy.scrollTo("gameAnalysis", anchor: .top)
              }
            }
            .id("gameAnalysis")
          }
        }
        #if os(macOS)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
        #endif
        .padding(.horizontal)
        .padding(.bottom)
      }
      .coordinateSpace(name: "gameAnalysisViewport")
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        viewportHeight = $0
      }
      .coordinateSpace(name: "scoringViewport")
      #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          Color.clear.frame(height: controlsHeight)
        }
      #else
        .safeAreaInset(edge: .bottom, spacing: 0) {
          ScoringToolbarView(state: store.scoringToolbarState) { store.send(.controlTapped($0)) }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .disabled(isPresentingPaywall || store.controlsPresentation != .shown)
        }
      #endif
        .background {
          TeamColorBackground(
            leftColor: store.courtLayout.left.team.bibColor,
            rightColor: store.courtLayout.right.team.bibColor
          )
          .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .toolbar {
          ToolbarItem(placement: .principal) {
            if isScoreboardAboveViewport {
              ScoringHeaderView(courtLayout: store.courtLayout)
            }
          }
          ToolbarItem(placement: .primaryAction) {
            Button {
              store.send(.undoButtonTapped)
            } label: {
              Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!store.canUndoGoal)
            .accessibilityLabel("Undo last goal")
          }

          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button {
                store.send(.swapSidesButtonTapped)
              } label: {
                Label("Swap sides", systemImage: "arrow.left.arrow.right")
              }
              .disabled(store.isSavingCourtOrientation || !store.canOperate)

              Button {
                store.send(.swapCentrePass)
              } label: {
                Label("Change centre pass", systemImage: "arrow.left.circle.fill")
              }
              .disabled(!store.canOperate)

              Button("End Quarter", systemImage: "forward.end.fill") {
                store.send(.endQuarterButtonTapped)
              }
              .disabled(!store.canMoveToNextQuarter)

            } label: {
              Label("Options", systemImage: "ellipsis")
            }
          }
        }
      #if os(iOS)
        .sheet(
          isPresented: .constant(store.controlsPresentation == .shown && !isPresentingPaywall),
          onDismiss: { store.send(.controlsSheetDidDismiss) }
        ) {
          ScoringToolbarView(state: store.scoringToolbarState) { store.send(.controlTapped($0)) }
            .ignoresSafeArea(.container, edges: .bottom)
            .presentationSizing(.fitted)
//            .presentationDetents([.height(110)])
            .presentationDetents(.sizeToFit)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled()
            .presentationDragIndicator(.hidden)
            .presentationPlacement(.leading)
        }
      #endif
        .sheet(
          item: $store.scope(state: \.timeInput, action: \.timeInput),
          onDismiss: { store.send(.timeInputSheetDidDismiss) }
        ) { TimeInputView(store: $0) }
        .alert($store.scope(state: \.alert, action: \.alert))
        .onChange(of: isPresentingPaywall) { wasPresented, isPresented in
          if wasPresented, !isPresented {
            store.send(.proPaywallDidDismiss)
          }
        }
        .onChange(of: proAccess) { _, access in
          if access == .pro {
            store.send(.proPaywallDidDismiss)
          }
        }
      #if os(iOS)
        .sensoryFeedback(
          .success,
          trigger: store.goalFeedbackTrigger,
          condition: { _, _ in store.hapticsEnabled }
        )
      #endif
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          await store.send(.keepScreenAwakeTask).finish()
        }
        .task {
          guard scenePhase == .active else { return }
          store.send(.sceneBecameActive)
        }
        .onChange(of: scenePhase, scenePhaseChanged)
      #if os(macOS)
        .focusedSceneValue(\.scoringCommands, ScoringCommandContext(store: store, isPresentingPaywall: isPresentingPaywall))
      #endif
    }
  }

  private func scenePhaseChanged(
    _: ScenePhase,
    _ newValue: ScenePhase
  ) {
    store.send(newValue == .active ? .sceneBecameActive : .sceneBecameInactive)
  }
}

#Preview("Scoring scenarios") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  ScoringScenarioPreview()
}

private struct ScoringScenarioPreview: View {
  @State private var scenario = ScoringPreviewScenario.running

  var body: some View {
    NavigationStack {
      ScoringView(store: scoringPreviewStore(scenario.state))
        .id(scenario)
        .toolbar {
          ToolbarItem(placement: .automatic) {
            Picker("Scenario", selection: $scenario) {
              ForEach(ScoringPreviewScenario.allCases) { Text($0.rawValue).tag($0) }
            }
          }
        }
    }
  }
}
