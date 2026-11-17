#if DEBUG
  import AlarmClient
  import ComposableArchitecture
  import Database
  import Foundation
  import GameCore
  import GameDetailFeature
  import GamesFeature
  import PreviewSupport
  import ScoringFeature
  import Sharing
  import SQLiteData
  import SubscriptionClient

  /// Explicit opt-in fixtures use temporary storage and never bootstrap live services.
  public enum GoalDeletionLaunchScenario: String {
    case running = "goal-deletion-running"
    case paused = "goal-deletion-paused"
    case breakTime = "goal-deletion-break"
    case completed = "goal-deletion-completed"
    case plannedGame = "planned-game"
    case customPeriodSetup = "custom-period-setup"
    case twelvePeriodGame = "twelve-period-game"

    private var isPlanned: Bool {
      self == .plannedGame || self == .customPeriodSetup
    }

    private var isCompleted: Bool {
      self == .completed || self == .twelvePeriodGame
    }

    private static var requested: Self? {
      guard let name = ProcessInfo.processInfo.environment["SUPERSHOT_LAUNCH_SCENARIO"] else { return nil }
      guard let scenario = Self(rawValue: name) else {
        preconditionFailure("Unknown SUPERSHOT_LAUNCH_SCENARIO: \(name)")
      }
      return scenario
    }

    @MainActor
    public static func prepareIfRequested() throws -> Bool {
      guard let scenario = requested else { return false }
      let defaults = UserDefaults.inMemory
      defaults.set(true, forKey: "hasCompletedWelcome")
      defaults.set(false, forKey: "soundEffectsEnabled")
      defaults.set(false, forKey: "hapticsEnabled")
      prepareDependencies {
        $0.context = .preview
        $0.defaultAppStorage = defaults
        $0.alarmClient = .noop
        $0.alarmAuthorization = .authorized
        $0.proSubscription = .free
      }
      try prepareDependencies {
        try $0.bootstrapDatabase(path: NSTemporaryDirectory() + "goal-deletion-\(UUID().uuidString).db")
      }
      @Dependency(\.defaultDatabase) var database
      try scenario.seed(database)
      return true
    }

    @MainActor
    package static func initialState() -> AppFeature.State {
      var state = AppFeature.State()
      guard let scenario = requested else { return state }
      state.destination = nil
      state.selectedTab = .games
      guard !scenario.isPlanned else { return state }
      @Dependency(\.defaultDatabase) var database
      let snapshot = try! database.read { try GameSnapshot.fetch($0, gameID: UUID(166)) }
      if scenario.isCompleted {
        state.games.path.append(.gameDetail(.init(gameID: snapshot.game.id)))
      } else {
        state.games.path.append(.scoring(ScoringFeature.State(snapshot: snapshot)))
      }
      return state
    }

    private func seed(_ database: any DatabaseWriter) throws {
      let now = Date.now
      let gameID = UUID(166)
      var fixturePeriods = MockGameData.periods(gameID: gameID, idOffset: 1660)
      if self == .twelvePeriodGame {
        fixturePeriods = (0 ..< 12).map { position in
          GamePeriod(
            id: UUID(1660 + position),
            gameID: gameID,
            position: position,
            durationSeconds: 480,
            breakAfterDurationSeconds: position < 11 ? 60 : nil
          )
        }
      } else if self == .customPeriodSetup {
        for index in fixturePeriods.indices {
          fixturePeriods[index].durationSeconds = 2
          fixturePeriods[index].breakAfterDurationSeconds = nil
        }
      }
      let periods = fixturePeriods
      let teamAName = self == .twelvePeriodGame ? "Hackney Foxes" : "Foxes"
      let teamBName = self == .twelvePeriodGame ? "Wanstead Owls" : "Owls"
      try database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: teamAName)
          Team(id: UUID(2), name: teamBName, colorHex: "#FF3B30")
        }.execute(db)
        try Game.insert {
          Game(
            id: gameID,
            startedAt: isPlanned ? nil : now.addingTimeInterval(-1200),
            endedAt: isCompleted ? now : nil,
            teamAID: UUID(1),
            teamBID: UUID(2),
            centrePassTeamID: UUID(1),
            lateScoringPeriodNumber: self == .breakTime ? 1 : nil,
            currentPhaseIndex: isCompleted ? (periods.count - 1) * 2 : self == .breakTime ? 1 : 0,
            elapsedSeconds: isCompleted ? 480 : self == .breakTime ? 15 : isPlanned ? 0 : 120,
            timerEndsAt: self == .running ? now.addingTimeInterval(360) : nil,
            court: isPlanned ? "3" : nil
          )
        }.execute(db)
        for period in periods {
          try GamePeriod.insert { period }.execute(db)
        }
        guard !isPlanned else { return }
        for index in 0 ..< 4 {
          try Goal.insert {
            Goal(
              id: UUID(16600 + index),
              gameID: gameID,
              gamePeriodID: periods[0].id,
              teamID: UUID(index.isMultiple(of: 2) ? 1 : 2),
              elapsedSeconds: 20 + index * 20,
              points: index == 0 ? 2 : 1,
              createdAt: now.addingTimeInterval(Double(-1200 + index * 20))
            )
          }.execute(db)
        }
      }
    }
  }
#endif
