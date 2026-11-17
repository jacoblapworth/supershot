#if os(macOS)
  import AlarmClient
  import AppKit
  import ComposableArchitecture
  import GamesFeature
  import NewGameFeature
  import PaywallFeature
  import PermissionsFeature
  import ScoringFeature
  import SettingsFeature
  import SwiftUI
  import TeamsFeature

  /// Both scenes use the same retained feature store and subscription observation.
  public struct SupershotMacScenes: Scene {
    @State private var store = Store(initialState: AppFeature.State()) { AppFeature() }

    public init() {}

    public var body: some Scene {
      Window("Supershot", id: "main") {
        AppView(store: store)
          .frame(minWidth: 760, minHeight: 560)
          .focusedSceneValue(\.supershotMainWindow, true)
      }
      .defaultSize(width: 1100, height: 760)
      .commands { MacAppCommands(store: store) }

      Settings {
        MacSettingsView(store: store)
      }
    }
  }

  private struct MacSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
      SettingsView(proAccess: store.proAccess, store: store.scope(state: \.settings, action: \.settings))
        .frame(width: 560, height: 540)
        .sheet(item: Binding(
          get: {
            store.paywallFromSettings
              ? store.scope(state: \.destination?.proPaywall, action: \.destination.proPaywall)
              : nil
          },
          set: {
            if $0 == nil {
              store.send(.destination(.dismiss))
            }
          }
        )) { PaywallView(store: $0) }
        .task { store.send(.task) }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active {
            store.send(.sceneBecameActive)
          }
        }
    }
  }

  private struct MainWindowKey: FocusedValueKey { typealias Value = Bool }
  extension FocusedValues {
    var supershotMainWindow: Bool? {
      get { self[MainWindowKey.self] }
      set { self[MainWindowKey.self] = newValue }
    }
  }

  private struct MacAppCommands: Commands {
    let store: StoreOf<AppFeature>
    @FocusedValue(\.supershotMainWindow) private var isMainWindow
    @FocusedValue(\.scoringCommands) private var scoring

    private var canNavigate: Bool {
      isMainWindow == true && !store.macHasBlockingPresentation
    }

    var body: some Commands {
      CommandGroup(replacing: .newItem) {
        Button("New Game") {
          store.send(.selectedTabChanged(.games))
          store.send(.games(.newGameButtonTapped))
        }
        .keyboardShortcut("n")
        .disabled(!canNavigate || !store.games.path.isEmpty)
        Button("New Team") {
          store.send(.selectedTabChanged(.teams))
          store.send(.teams(.newTeamButtonTapped))
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(!canNavigate || !store.teams.path.isEmpty)
      }
      CommandGroup(after: .sidebar) {
        Button("Games") { store.send(.selectedTabChanged(.games)) }
          .keyboardShortcut("1").disabled(!canNavigate)
        Button("Teams") { store.send(.selectedTabChanged(.teams)) }
          .keyboardShortcut("2").disabled(!canNavigate)
      }
      CommandMenu("Game") {
        Button(scoring?.timerTitle ?? "Start Timer") { scoring?.toggleTimer() }
          .keyboardShortcut("p", modifiers: [.command, .shift])
          .disabled(scoring?.canToggleTimer != true)
        Button(scoring?.leftTitle ?? "Goal for Left Team") { scoring?.goal(left: true) }
          .keyboardShortcut("l", modifiers: [.command, .shift])
          .disabled(scoring?.canScore != true)
        Button(scoring?.rightTitle ?? "Goal for Right Team") { scoring?.goal(left: false) }
          .keyboardShortcut("r", modifiers: [.command, .shift])
          .disabled(scoring?.canScore != true)
      }
      if let scoring, scoring.isEnabled {
        CommandGroup(replacing: .undoRedo) {
          Button("Undo Last Goal") { scoring.undo() }
            .keyboardShortcut("z")
            .disabled(!scoring.canUndo)
        }
      }
    }
  }

  struct MacNavigationView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
      NavigationSplitView {
        List(selection: Binding<AppFeature.Tab?>(
          get: { store.selectedTab },
          set: {
            if let tab = $0 {
              store.send(.selectedTabChanged(tab))
            }
          }
        )) {
          Label("Games", systemImage: "sportscourt").tag(AppFeature.Tab.games)
          Label("Teams", systemImage: "person.2").tag(AppFeature.Tab.teams)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
        .navigationTitle("Supershot")
        .disabled(store.macHasBlockingPresentation)
      } detail: {
        switch store.selectedTab {
        case .teams:
          TeamsListView(
            proAccess: store.proAccess,
            store: store.scope(state: \.teams, action: \.teams),
            isPresentingPaywall: store.destination?.proPaywall != nil
          )
        case .games, .settings:
          GamesHomeView(
            proAccess: store.proAccess,
            store: store.scope(state: \.games, action: \.games),
            isPresentingPaywall: store.destination?.proPaywall != nil
          )
        }
      }
    }
  }

  package extension AppFeature.State {
    var macHasBlockingPresentation: Bool {
      if destination != nil || games.alert != nil || teams.destination != nil
        || games.newGame != nil || teams.newGame != nil
        || settings.timeInput != nil || games.pendingGameResume != nil
        || teams.pendingGameResume != nil
      {
        return true
      }
      for path in games.path {
        switch path {
        case let .scoring(state):
          if state.timeInput != nil || state.alert != nil || state.controlsPresentation != .shown
            || state.operation != nil
          {
            return true
          }
        case .gameDetail: break
        }
      }
      for path in teams.path {
        switch path {
        case let .scoring(state):
          if state.timeInput != nil || state.alert != nil || state.controlsPresentation != .shown
            || state.operation != nil
          {
            return true
          }
        case let .teamDetail(state):
          if state.editor != nil {
            return true
          }
        case .gameDetail: break
        }
      }
      return false
    }
  }
#endif
