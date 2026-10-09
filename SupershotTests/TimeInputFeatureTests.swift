import ComposableArchitecture
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct TimeInputFeatureTests {
    @Test func digitsReplaceThenAppendAndSecondsCarry() async {
      let store = TestStore(
        initialState: TimeInputFeature.State(
          title: "Time", totalSeconds: 480, allowedSeconds: 0...5999
        )
      ) { TimeInputFeature() }
      await store.send(.digitButtonTapped(1)) {
        $0.minutes = "1"
        $0.replacesNextDigit = false
      }
      await store.send(.digitButtonTapped(2)) { $0.minutes = "12" }
      await store.send(.digitButtonTapped(3))
      await store.send(.unitButtonTapped(.seconds)) {
        $0.selectedUnit = .seconds
        $0.replacesNextDigit = true
      }
      await store.send(.digitButtonTapped(9)) {
        $0.seconds = "9"
        $0.replacesNextDigit = false
      }
      await store.send(.digitButtonTapped(0)) { $0.seconds = "90" }
      await store.send(.doneButtonTapped) {
        $0.minutes = "13"
        $0.seconds = "30"
      }
      await store.receive(\.delegate.committed)
      #expect(store.state.totalSeconds == 810)
    }

    @Test func quickAddUsesSelectedUnitAndCarries() async {
      let store = TestStore(
        initialState: TimeInputFeature.State(
          title: "Time", totalSeconds: 3590, allowedSeconds: 0...5999, selectedUnit: .seconds
        )
      ) { TimeInputFeature() }
      await store.send(.quickAddButtonTapped(30)) {
        $0.minutes = "60"
        $0.seconds = "20"
      }
      await store.send(.unitButtonTapped(.minutes)) { $0.selectedUnit = .minutes }
      await store.send(.quickAddButtonTapped(10)) { $0.minutes = "70" }
      await store.send(.digitButtonTapped(2)) {
        $0.minutes = "2"
        $0.replacesNextDigit = false
      }
      await store.send(.backspaceButtonTapped) { $0.minutes = "" }
      #expect(store.state.totalSeconds == 20)
    }

    @Test func maximumAndZeroValidation() async {
      let store = TestStore(
        initialState: TimeInputFeature.State(
          title: "Time", totalSeconds: 5999, allowedSeconds: 1...5999, selectedUnit: .seconds
        )
      ) { TimeInputFeature() }
      #expect(store.state.isValid)
      #expect(!store.state.canAdd(1))
      await store.send(.quickAddButtonTapped(1))
      await store.send(.digitButtonTapped(9)) {
        $0.seconds = "9"
        $0.replacesNextDigit = false
      }
      await store.send(.digitButtonTapped(9)) { $0.seconds = "99" }
      #expect(!store.state.isValid)
      await store.send(.doneButtonTapped)
      #expect(
        !TimeInputFeature.State(title: "Quarter", totalSeconds: 0, allowedSeconds: 1...5999).isValid
      )
      #expect(
        TimeInputFeature.State(title: "Break", totalSeconds: 0, allowedSeconds: 0...5999).isValid)
    }

    @Test func setupSheetCommitsOnlyIntoParentDraft() async {
      let store = TestStore(initialState: SetupTimingFeature.State(timing: SetupTiming())) {
        SetupTimingFeature()
      }
      await store.send(.editDurationButtonTapped(.allBreaks)) {
        $0.editedDuration = .allBreaks
        $0.timeInput = .init(title: "Break length", totalSeconds: 60, allowedSeconds: 0...5999)
      }
      await store.send(.timeInput(.presented(.quickAddButtonTapped(1)))) {
        $0.timeInput?.minutes = "2"
      }
      #expect(store.state.timing.firstBreakDuration.totalSeconds == 60)
      await store.send(.timeInput(.presented(.doneButtonTapped)))
      await store.receive(\.timeInput.presented.delegate.committed) {
        $0.timing.firstBreakDuration = .init(totalSeconds: 120)
        $0.timing.halfTimeDuration = .init(totalSeconds: 120)
        $0.timing.secondBreakDuration = .init(totalSeconds: 120)
        $0.timeInput = nil
        $0.editedDuration = nil
      }
    }

    @Test func settingsCancellationAndCommit() async {
      let state = SettingsFeature.State()
      state.$defaultPeriodDurationSeconds.withLock { $0 = 480 }
      let store = TestStore(initialState: state) { SettingsFeature() }
      await store.send(.editDefaultButtonTapped(.quarter)) {
        $0.editedDefault = .quarter
        $0.timeInput = .init(title: "Quarter length", totalSeconds: 480, allowedSeconds: 1...5999)
      }
      await store.send(.timeInput(.presented(.quickAddButtonTapped(1)))) {
        $0.timeInput?.minutes = "9"
      }
      await store.send(.timeInput(.dismiss)) {
        $0.timeInput = nil
        $0.editedDefault = nil
      }
      #expect(store.state.defaultPeriodDurationSeconds == 480)
      await store.send(.editDefaultButtonTapped(.quarter)) {
        $0.editedDefault = .quarter
        $0.timeInput = .init(title: "Quarter length", totalSeconds: 480, allowedSeconds: 1...5999)
      }
      await store.send(.timeInput(.presented(.quickAddButtonTapped(1)))) {
        $0.timeInput?.minutes = "9"
      }
      await store.send(.timeInput(.presented(.delegate(.committed(540))))) {
        $0.$defaultPeriodDurationSeconds.withLock { $0 = 540 }
        $0.timeInput = nil
        $0.editedDefault = nil
      }
    }
  }
}
