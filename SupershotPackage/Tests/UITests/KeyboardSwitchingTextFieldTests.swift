#if os(iOS)
  import AppUI
  import SwiftUI
  import Testing
  @testable import UI
  import UIKit

  @Suite(.serialized)
  @MainActor
  struct KeyboardSwitchingTextFieldTests {
    @Test
    func switchingRefreshesTheActiveResponderWithoutLosingSelection() throws {
      let field = TrackingTextField()
      let controller = makeController(textField: field)
      let window = show(controller)
      defer { window.isHidden = true }
      controller.updateText("Court 12")
      #expect(field.becomeFirstResponder())
      let start = try #require(field.position(from: field.beginningOfDocument, offset: 2))
      let end = try #require(field.position(from: start, offset: 3))
      field.selectedTextRange = field.textRange(from: start, to: end)
      let initialRefreshes = field.refreshCount
      let accessory = field.inputAccessoryViewController

      controller.selectOption(id: KeyboardOption.alphabet.id)

      #expect(field.keyboardType == .asciiCapable)
      #expect(field.isFirstResponder)
      #expect(field.refreshCount == initialRefreshes + 1)
      #expect(field.text == "Court 12")
      #expect(selectionOffsets(field) == [2, 5])
      #expect(field.inputAccessoryViewController === accessory)

      controller.selectOption(id: KeyboardOption.numeric.id)
      #expect(field.keyboardType == .numberPad)
      #expect(field.isFirstResponder)
      #expect(selectionOffsets(field) == [2, 5])
      #expect(field.refreshCount == initialRefreshes + 2)

      controller.selectOption(id: KeyboardOption.numeric.id)
      #expect(field.refreshCount == initialRefreshes + 2)
    }

    @Test
    func accessoriesAndSelectionsBelongToIndividualInputs() {
      let court = makeController()
      let division = makeController()
      let ordinary = UITextField()
      #expect(court.textField.inputAccessoryViewController != nil)
      #expect(division.textField.inputAccessoryViewController != nil)
      #expect(court.textField.inputAccessoryViewController !== division.textField.inputAccessoryViewController)
      #expect(ordinary.inputAccessoryView == nil)

      court.selectOption(id: KeyboardOption.alphabet.id)
      #expect(court.textField.keyboardType == .asciiCapable)
      #expect(division.textField.keyboardType == .numberPad)
      court.configure(options: [.alphabet, .numeric], initialOption: .numeric)
      #expect(court.selectedOptionID == KeyboardOption.alphabet.id)

      let host = UIViewController()
      host.loadViewIfNeeded()
      for controller in [court, division] {
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
      }
      host.view.addSubview(ordinary)
      let window = show(host)
      defer { window.isHidden = true }
      #expect(court.textField.becomeFirstResponder())
      #expect(division.textField.becomeFirstResponder())
      #expect(!court.textField.isFirstResponder)
      #expect(division.textField.keyboardType == .numberPad)
      #expect(ordinary.becomeFirstResponder())
      #expect(ordinary.inputAccessoryView == nil)
      #expect(court.textField.becomeFirstResponder())
      #expect(court.textField.keyboardType == .asciiCapable)
    }

    @Test
    func oneOptionHasNoAccessoryAndCleanupRemovesHostingChild() {
      let single = KeyboardTextFieldController(options: [.numeric], initialOption: .numeric)
      single.loadViewIfNeeded()
      #expect(single.textField.inputAccessoryViewController == nil)
      #expect(single.children.isEmpty)

      let controller = makeController()
      let accessory = controller.textField.inputAccessoryViewController
      let accessoryHost = accessory?.children.first
      #expect(accessoryHost != nil)
      #expect(accessoryHost?.parent === accessory)
      controller.tearDownAccessory()
      #expect(controller.textField.inputAccessoryViewController == nil)
      #expect(accessoryHost?.parent == nil)
      #expect(accessoryHost?.view.superview == nil)
      #expect(accessory?.children.isEmpty == true)
    }

    @Test
    func externalUpdatesAndEchoedEditsPreserveCursor() throws {
      let controller = makeController()
      let field = controller.textField
      controller.updateText("1234")
      let cursor = try #require(field.position(from: field.beginningOfDocument, offset: 2))
      field.selectedTextRange = field.textRange(from: cursor, to: cursor)
      controller.updateText("1234")
      #expect(selectionOffsets(field) == [2, 2])
      controller.updateText("12X34")
      #expect(field.text == "12X34")
      #expect(selectionOffsets(field) == [2, 2])
      controller.updateText("1")
      #expect(selectionOffsets(field) == [1, 1])
    }

    @Test
    func hostedFieldWritesEditsToItsBinding() async throws {
      var text = "12"
      let host = UIHostingController(rootView: KeyboardSwitchingTextField(
        "Court",
        text: Binding(get: { text }, set: { text = $0 }),
        keyboardTypes: [.alphabet, .numeric],
        initialKeyboardType: .numeric,
        accessibilityIdentifier: "test.court"
      ))
      let window = show(host)
      defer { window.isHidden = true }
      await Task.yield()
      host.view.layoutIfNeeded()
      let field = try #require(findTextField(in: host.view))
      #expect(field.text == "12")
      #expect(field.accessibilityLabel == "Court")
      #expect(field.accessibilityIdentifier == "test.court")
      #expect(field.inputAccessoryViewController != nil)
      #expect(field.becomeFirstResponder())
      let cursor = try #require(field.position(from: field.beginningOfDocument, offset: 1))
      field.selectedTextRange = field.textRange(from: cursor, to: cursor)
      field.insertText("A")
      // The scene-less package runner cannot route UIApplication control actions. Deliver
      // the field's registered editing action directly to verify its actual binding wiring.
      let target = try #require(field.allTargets.first?.base as? NSObject)
      let action = try #require(field.actions(forTarget: target, forControlEvent: .editingChanged)?.first)
      _ = target.perform(NSSelectorFromString(action), with: field)
      #expect(text == "1A2")
      #expect(selectionOffsets(field) == [2, 2])
    }

    @Test
    func hostedFieldUsesSwiftUIAppearanceAndTextSize() async throws {
      let host = UIHostingController(rootView: KeyboardSwitchingTextField(
        "Court",
        text: .constant("12"),
        keyboardTypes: [.alphabet, .numeric],
        initialKeyboardType: .numeric
      )
      .environment(\.colorScheme, .dark)
      .environment(\.dynamicTypeSize, .accessibility3))
      let window = show(host)
      defer { window.isHidden = true }
      await Task.yield()
      host.view.layoutIfNeeded()
      let field = try #require(findTextField(in: host.view))
      #expect(field.textColor == UIColor.label)
      #expect(field.keyboardAppearance == .dark)
      let expectedFont = UIFont.preferredFont(
        forTextStyle: .body,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
      )
      #expect(field.font?.pointSize == expectedFont.pointSize)
      #expect(field.inputAccessoryViewController?.overrideUserInterfaceStyle == .dark)
    }

    private func makeController(textField: KeyboardUITextField? = nil) -> KeyboardTextFieldController {
      let controller = KeyboardTextFieldController(options: [.alphabet, .numeric], initialOption: .numeric, textField: textField)
      controller.loadViewIfNeeded()
      return controller
    }

    private func show(_ controller: UIViewController) -> UIWindow {
      // The package test runner has no UIWindowScene; its test windows require the legacy initializer.
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
      window.rootViewController = controller
      window.makeKeyAndVisible()
      controller.view.layoutIfNeeded()
      return window
    }

    private func selectionOffsets(_ field: UITextField) -> [Int] {
      guard let range = field.selectedTextRange else { return [] }
      return [
        field.offset(from: field.beginningOfDocument, to: range.start),
        field.offset(from: field.beginningOfDocument, to: range.end),
      ]
    }

    private func findTextField(in view: UIView) -> UITextField? {
      if let field = view as? UITextField {
        return field
      }
      return view.subviews.lazy.compactMap { findTextField(in: $0) }.first
    }
  }

  private final class TrackingTextField: KeyboardUITextField {
    var refreshCount = 0

    override func reloadInputViews() {
      refreshCount += 1
      super.reloadInputViews()
    }
  }
#endif
