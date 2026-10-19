#if os(macOS)
  import ComposableArchitecture
  import SwiftUI

  struct MacTimeInputFields: View {
    @Bindable var store: StoreOf<TimeInputFeature>
    @FocusState private var focusedUnit: TimeInputFeature.Unit?

    var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading) {
          Text("Minutes")
          TextField(
            "Minutes",
            text: Binding(get: { store.minutes }, set: { store.send(.textChanged(.minutes, $0)) })
          )
          .focused($focusedUnit, equals: .minutes)
          .accessibilityLabel("Minutes")
        }
        Text(":").font(.title).accessibilityHidden(true)
        VStack(alignment: .leading) {
          Text("Seconds")
          TextField(
            "Seconds",
            text: Binding(get: { store.seconds }, set: { store.send(.textChanged(.seconds, $0)) })
          )
          .focused($focusedUnit, equals: .seconds)
          .accessibilityLabel("Seconds")
        }
      }
      .textFieldStyle(.roundedBorder)
      .monospacedDigit()
      .disabled(store.isSaving)
      .onSubmit { store.send(.doneButtonTapped) }
      .task { focusedUnit = store.selectedUnit }
    }
  }

  #Preview {
    MacTimeInputFields(
      store: Store(
        initialState: TimeInputFeature.State(
          title: "Quarter length", totalSeconds: 480, allowedSeconds: 1...5999)
      ) {
        TimeInputFeature()
      }
    )
    .padding()
  }
#endif
