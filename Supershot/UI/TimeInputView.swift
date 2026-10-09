import ComposableArchitecture
import SwiftUI

struct TimeInputView: View {
  @Bindable var store: StoreOf<TimeInputFeature>
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        TimeInputDisplay(store: store)
        TimeInputKeypad(store: store)
        if let error = store.errorMessage {
          Text(error).foregroundStyle(.red)
        } else if !store.isValid {
          Text(
            "Enter a time between \(formatted(store.allowedSeconds.lowerBound)) and \(formatted(store.allowedSeconds.upperBound))."
          )
          .foregroundStyle(.red)
        }
        if store.isSaving { ProgressView("Saving time…") }
      }
      .padding(24)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
      .navigationTitle(store.title)
#if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
#endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { store.send(.cancelButtonTapped) }
            .disabled(store.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", systemImage: "checkmark") { store.send(.doneButtonTapped) }
            .disabled(!store.isValid || store.isSaving)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationBackground(.regularMaterial)
    .interactiveDismissDisabled(store.isSaving)
  }
  
  private func formatted(_ seconds: Int) -> String {
    "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }
}

private struct TimeInputDisplay: View {
  let store: StoreOf<TimeInputFeature>
  
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      field(.minutes, value: store.minutes, label: "Minutes")
      Text(":").font(.system(size: 56, weight: .bold, design: .rounded))
        .accessibilityHidden(true)
        .padding(.vertical, 12)
      field(.seconds, value: store.seconds, label: "Seconds")
    }
    .glassEffect(in: RoundedRectangle(cornerRadius: 28))
    .environment(\.layoutDirection, .leftToRight)
  }
  
  private func field(_ unit: TimeInputFeature.Unit, value: String, label: String) -> some View {
    Button {
      store.send(.unitButtonTapped(unit))
    } label: {
      VStack(spacing: 8) {
        Text(String(format: "%02d", Int(value) ?? 0))
          .font(.system(size: 64, weight: .bold, design: .rounded))
          .monospacedDigit()
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .padding(.horizontal, 12)
          .overlay {
            RoundedRectangle(cornerRadius: 20)
              .strokeBorder(store.selectedUnit == unit ? Color.accentColor : .clear, lineWidth: 3)
          }
        Text(label).font(.subheadline)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    }
    .buttonStyle(.plain)
    .disabled(store.isSaving)
    .accessibilityLabel(label)
    .accessibilityValue(value.isEmpty ? "0" : value)
    .accessibilityAddTraits(store.selectedUnit == unit ? .isSelected : [])
    .accessibilityHint("Select to edit with the keypad")
  }
}

private struct TimeInputKeypad: View {
  let store: StoreOf<TimeInputFeature>
  
  var body: some View {
    Grid(horizontalSpacing: 10, verticalSpacing: 14) {
      GridRow {
        add(1)
        digit(7)
        digit(8)
        digit(9)
        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
      }
      GridRow {
        add(10)
        digit(4)
        digit(5)
        digit(6)
        digit(0)
      }
      GridRow {
        add(30)
        digit(1)
        digit(2)
        digit(3)
        key(tint: .red) {
          store.send(.backspaceButtonTapped)
        } label: {
          Image(systemName: "delete.left").accessibilityLabel("Backspace")
        }
      }
    }
    .disabled(store.isSaving)
    .environment(\.layoutDirection, .leftToRight)
  }
  
  private func add(_ amount: Int) -> some View {
    key(tint: .green) {
      store.send(.quickAddButtonTapped(amount))
    } label: {
      Text("+\(amount)")
    }
    .disabled(!store.enabledQuickAdds.contains(amount))
    .accessibilityLabel("Add \(amount) \(store.selectedUnit == .minutes ? "minutes" : "seconds")")
  }
  
  private func digit(_ value: Int) -> some View {
    key {
      store.send(.digitButtonTapped(value))
    } label: {
      Text("\(value)")
    }
  }
  
  private func key<Label: View>(
    tint: Color = .primary, action: @escaping () -> Void, @ViewBuilder label: () -> Label
  ) -> some View {
    Button(action: action) {
      label()
        .font(.title2.bold())
        .fontDesign(.rounded)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }
    .tint(tint.opacity(0.2))
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
  }
}

#Preview {
  NavigationStack {}
    .sheet(isPresented: .constant(true)) {
      TimeInputView(
        store: Store(
          initialState: TimeInputFeature.State(
            title: "Quarter length",
            totalSeconds: 480,
            allowedSeconds: 1...5999
          )
        ) { TimeInputFeature() })
    }
}
