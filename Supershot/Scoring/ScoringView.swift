import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Fetch private var analysisResponse: GameAnalysisRequest.Value
  @State private var selectedAnalysis = GameAnalysisTab.playByPlay
  @State private var viewportHeight: CGFloat = 0
  @State private var isScoreboardAboveViewport = false
  @Bindable var store: StoreOf<ScoringFeature>
  let proAccess: SubscriptionEntitlement
  let isPresentingPaywall: Bool

  init(
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

  var body: some View {
    ScrollViewReader { scrollProxy in
      ScrollView {
        LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {

          VStack {
            TimerView(
              canEditTime: store.canEditTime,
              editTimeTapped: { store.send(.editTimeButtonTapped) },
              clockPhase: store.clockPhase,
              currentDurationSeconds: store.currentDurationSeconds,
              elapsedSeconds: store.elapsedSeconds,
              isPeriodComplete: store.isPeriodComplete,
              isShowingLastCentrePassBanner: store.isShowingLastCentrePassBanner,
              isTimerRunning: store.isTimerRunning,
              period: store.period,
              pauseTimerTapped: { store.send(.pauseTimerButtonTapped) },
              skipBreakTapped: { store.send(.skipBreakButtonTapped) },
              startTimerTapped: { store.send(.startTimerButtonTapped) }
            )

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
          if store.isShowingLastCentrePassBanner {
            LastCentrePassBanner(
              centrePassTeam: store.centrePassTeam,
              isTransitioningPeriod: store.isTransitioningPeriod,
              period: store.lastCompletedQuarterNumber,
              lastCentrePassNotTakenTapped: {
                store.send(.lastCentrePassNotTakenButtonTapped)
              },
              lastCentrePassTakenTapped: {
                store.send(.lastCentrePassTakenButtonTapped)
              }
            )
          }

          if store.canFinishGame {
            ScoringGameControls(
              canFinishGame: store.canFinishGame,
              canMoveToNextQuarter: store.canMoveToNextQuarter,
              clockPhase: store.clockPhase,
              isShowingLastCentrePassBanner: store.isShowingLastCentrePassBanner,
              isTransitioningPeriod: store.isTransitioningPeriod,
              period: store.period,
              endQuarterTapped: { store.send(.endQuarterButtonTapped) },
              finishGameTapped: { store.send(.finishGameButtonTapped) },
              skipBreakTapped: { store.send(.skipBreakButtonTapped) }
            )
          }

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
        .padding(.horizontal)
        .padding(.bottom)

      }
      .coordinateSpace(name: "gameAnalysisViewport")
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
      .coordinateSpace(name: "scoringViewport")
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Color
          .clear
          .frame(height: 112)
      }
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
            .disabled(store.isSavingCourtOrientation)

            Button {
              store.send(.swapCentrePass)
            } label: {
              Label("Change centre pass", systemImage: "arrow.left.circle.fill")
            }

          } label: {
            Label("Options", systemImage: "ellipsis")
          }
        }

      }
      .sheet(
        isPresented: .constant(store.controlsPresentation == .shown && !isPresentingPaywall),
        onDismiss: { store.send(.controlsSheetDidDismiss) },
        content: {
            VStack(alignment: .leading, spacing: 12) {
              if store.canScoreGoal {
                HStack(spacing: 16) {
                  goalButton(for: store.courtLayout.left)
                  goalButton(for: store.courtLayout.right)
                }
                .environment(\.layoutDirection, .leftToRight)
              } else if store.currentPhase.isPlayingPeriod && !store.isPeriodComplete && !store.isShowingLastCentrePassBanner {
                Button(action: { store.send(.startTimerButtonTapped) }) {
                  Label("Start Quarter", systemImage: "play.fill")
                    .fontWeight(.medium)
                    .padding(8)
                }
                .tint(.green)
              }
            }
            .padding()
          .buttonSizing(.flexible)
          .buttonStyle(.glassProminent)
          .presentationDetents(.sizeToFit)
          .presentationBackgroundInteraction(.enabled)
          .presentationBackground(alignment: .topLeading) {}
          .interactiveDismissDisabled()
          .presentationContentInteraction(.resizes)
          .presentationDragIndicator(.hidden)
  #if os(iOS)
          .presentationPlacement(.leading)
  #endif
        })
      .sheet(
        item: $store.scope(state: \.timeInput, action: \.timeInput),
        onDismiss: { store.send(.timeInputSheetDidDismiss) }
      ) { TimeInputView(store: $0) }
        .alert($store.scope(state: \.alert, action: \.alert))
        .onChange(of: isPresentingPaywall) { wasPresented, isPresented in
          if wasPresented && !isPresented { store.send(.proPaywallDidDismiss) }
        }
        .onChange(of: proAccess) { _, access in
          if access == .pro { store.send(.proPaywallDidDismiss) }
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
    }
  }

  private func goalButton(for courtTeam: ScoringFeature.CourtTeam) -> some View {
    Button(action: { store.send(.goalButtonTapped(courtTeam.id)) }) {
      Label("Goal", systemImage: "plus")
        .padding(24)
    }
    .tint(courtTeam.team.bibColor)
    .accessibilityLabel("Goal for \(courtTeam.team.name)")
    .font(.title2.bold())
    .labelStyle(.iconOnly)
  }

  private func scenePhaseChanged(
    _ oldValue: ScenePhase,
    _ newValue: ScenePhase
  ) {
    store.send(newValue == .active ? .sceneBecameActive : .sceneBecameInactive)
  }
}

#Preview("Quarter") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  NavigationStack {
    ScoringView(store: scoringPreviewStore(.previewQuarter))
  }
}

#Preview("Quarter complete") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  NavigationStack {
    ScoringView(store: scoringPreviewStore(.previewQuarterComplete))
  }
}

#Preview("Break") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  NavigationStack {
    ScoringView(store: scoringPreviewStore(.previewBreak))
  }
}
