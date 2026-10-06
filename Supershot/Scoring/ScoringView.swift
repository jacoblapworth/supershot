import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Fetch private var timelineResponse: GoalTimelineRequest.Value
  @Bindable var store: StoreOf<ScoringFeature>
  
  init(store: StoreOf<ScoringFeature>) {
    self.store = store
    _timelineResponse = Fetch(
      wrappedValue: GoalTimelineRequest.Value(
        timeline: .empty(through: store.period)
      ),
      GoalTimelineRequest(gameID: store.gameID),
      animation: .default
    )
  }
  
  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        
        VStack {
          TimerView(
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
          
        }
        
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
        
        GoalTimelineView(
          teamABibColor: store.teamA.bibColor,
          teamAName: store.teamA.name,
          teamBBibColor: store.teamB.bibColor,
          teamBName: store.teamB.name,
          timeline: timelineResponse.timeline
        )
      }
      .padding()
      
    }
//    .background {
//      LinearGradient(colors: [store.teamA.bibColor, store.teamB.bibColor], startPoint: .leading, endPoint: .trailing)
//        .ignoresSafeArea()
//    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.undoButtonTapped)
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!store.canUndo || store.isShowingLastCentrePassBanner)
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
            
          } label: {
            Label("Change centre pass", systemImage: "arrow.left.circle.fill")
          }
          
        } label: {
          Label("Options", systemImage: "ellipsis")
        }
      }
      
    }
    //    .background {
    //      LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
    //        .ignoresSafeArea()
    //    }
    .sheet(isPresented: .constant(true), content: {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if store.canScoreGoal {
            HStack(spacing: 16) {
              goalButton(for: store.courtLayout.left)
              goalButton(for: store.courtLayout.right)
            }
            .environment(\.layoutDirection, .leftToRight)
          } else {
            Button(action: { store.send(.startTimerButtonTapped) }) {
              Label("Start Quarter", systemImage: "play.fill")
                .fontWeight(.medium)
                .padding(8)
            }
            .tint(.green)
          }
          CentrePassControl(
            courtLayout: store.courtLayout,
            centrePassTeamTapped: { store.send(.centrePassTeamButtonTapped($0)) }
          )
        }
        .padding()
      }
      .presentationBackground(.thinMaterial)
      .scrollDisabled(true)
      .buttonSizing(.flexible)
      .buttonStyle(.glassProminent)
      .presentationDetents([.height(84), .height(200)],
        selection: $store.presentationDetent)
      .presentationPlacement(.leading)
      .presentationBackgroundInteraction(.enabled)
      .presentationBackground(alignment: .topLeading) {}
      .interactiveDismissDisabled()
      //      .presentationContentInteraction(.resizes)
      //      .presentationDragIndicator(.hidden)
      //      .presentationBackground(.ultraThinMaterial)
      //      .presentationSizing(.fitted)
    })
    .alert($store.scope(state: \.alert, action: \.alert))
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
  
  private func goalButton(for courtTeam: ScoringFeature.CourtTeam) -> some View {
    Button(action: { store.send(.goalButtonTapped(courtTeam.id)) }) {
      Label("Goal", systemImage: "plus")
        .padding(8)
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
