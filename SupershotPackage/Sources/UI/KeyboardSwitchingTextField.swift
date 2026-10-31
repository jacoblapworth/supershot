import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Presentation and input traits for one choice in a keyboard accessory.
package struct KeyboardOption: Identifiable {
  package let id: String
  package let title: LocalizedStringResource
  package let accessibilityLabel: LocalizedStringResource
  package let systemImage: String
  #if os(iOS)
    package let keyboardType: UIKeyboardType

    package init(
      id: String,
      title: LocalizedStringResource,
      accessibilityLabel: LocalizedStringResource,
      keyboardType: UIKeyboardType,
      systemImage: String
    ) {
      self.id = id
      self.title = title
      self.accessibilityLabel = accessibilityLabel
      self.keyboardType = keyboardType
      self.systemImage = systemImage
    }
  #else
    private init(id: String, title: LocalizedStringResource, accessibilityLabel: LocalizedStringResource, systemImage: String) {
      self.id = id
      self.title = title
      self.accessibilityLabel = accessibilityLabel
      self.systemImage = systemImage
    }
  #endif

  package static var alphabet: Self {
    #if os(iOS)
      Self(id: "alphabet", title: "ABC", accessibilityLabel: "Alphabet keyboard", keyboardType: .asciiCapable, systemImage: "textformat.characters")
    #else
      Self(id: "alphabet", title: "ABC", accessibilityLabel: "Alphabet keyboard", systemImage: "textformat.characters")
    #endif
  }

  package static var numeric: Self {
    #if os(iOS)
      Self(id: "numeric", title: "123", accessibilityLabel: "Numeric keyboard", keyboardType: .numberPad, systemImage: "numbers")
    #else
      Self(id: "numeric", title: "123", accessibilityLabel: "Numeric keyboard", systemImage: "numbers")
    #endif
  }
}

/// A plain, trailing-aligned input whose keyboard choices belong to this field alone.
package struct KeyboardSwitchingTextField: View {
  private let title: LocalizedStringResource
  @Binding private var text: String
  private let keyboardTypes: [KeyboardOption]
  private let initialKeyboardType: KeyboardOption
  private let accessibilityIdentifier: String

  package init(
    _ title: LocalizedStringResource,
    text: Binding<String>,
    keyboardTypes: [KeyboardOption],
    initialKeyboardType: KeyboardOption,
    accessibilityIdentifier: String = ""
  ) {
    precondition(!keyboardTypes.isEmpty, "Provide at least one keyboard option.")
    precondition(Set(keyboardTypes.map(\.id)).count == keyboardTypes.count, "Keyboard option IDs must be unique.")
    precondition(keyboardTypes.contains { $0.id == initialKeyboardType.id }, "The initial keyboard must be an available option.")
    self.title = title
    _text = text
    self.keyboardTypes = keyboardTypes
    self.initialKeyboardType = initialKeyboardType
    self.accessibilityIdentifier = accessibilityIdentifier
  }

  package var body: some View {
    #if os(iOS)
      KeyboardTextFieldRepresentable(
        title: title,
        text: $text,
        options: keyboardTypes,
        initialOption: initialKeyboardType,
        accessibilityIdentifier: accessibilityIdentifier
      )
    #else
      TextField("", text: $text)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(accessibilityIdentifier)
    #endif
  }
}

#if os(iOS)
  private struct KeyboardTextFieldRepresentable: UIViewControllerRepresentable {
    let title: LocalizedStringResource
    @Binding var text: String
    let options: [KeyboardOption]
    let initialOption: KeyboardOption
    let accessibilityIdentifier: String
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
      Coordinator(text: $text)
    }

    func makeUIViewController(context: Context) -> KeyboardTextFieldController {
      let controller = KeyboardTextFieldController(options: options, initialOption: initialOption)
      controller.loadViewIfNeeded()
      controller.textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
      return controller
    }

    func updateUIViewController(_ controller: KeyboardTextFieldController, context: Context) {
      context.coordinator.text = $text
      controller.configureAppearance(
        style: colorScheme == .dark ? .dark : .light,
        contentSizeCategory: contentSizeCategory
      )
      controller.configure(options: options, initialOption: initialOption)
      controller.updateText(text)
      controller.textField.accessibilityLabel = String(localized: title)
      controller.textField.accessibilityIdentifier = accessibilityIdentifier
      controller.textField.isEnabled = isEnabled
    }

    private var contentSizeCategory: UIContentSizeCategory {
      switch dynamicTypeSize {
      case .xSmall: .extraSmall
      case .small: .small
      case .medium: .medium
      case .large: .large
      case .xLarge: .extraLarge
      case .xxLarge: .extraExtraLarge
      case .xxxLarge: .extraExtraExtraLarge
      case .accessibility1: .accessibilityMedium
      case .accessibility2: .accessibilityLarge
      case .accessibility3: .accessibilityExtraLarge
      case .accessibility4: .accessibilityExtraExtraLarge
      case .accessibility5: .accessibilityExtraExtraExtraLarge
      @unknown default: .large
      }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: KeyboardTextFieldController, context _: Context) -> CGSize? {
      CGSize(
        width: proposal.width ?? uiViewController.textField.intrinsicContentSize.width,
        height: max(30, uiViewController.textField.intrinsicContentSize.height)
      )
    }

    static func dismantleUIViewController(_ controller: KeyboardTextFieldController, coordinator: Coordinator) {
      controller.textField.removeTarget(coordinator, action: nil, for: .allEvents)
      controller.tearDownAccessory()
    }

    final class Coordinator: NSObject {
      var text: Binding<String>

      init(text: Binding<String>) {
        self.text = text
      }

      @objc func textChanged(_ sender: UITextField) {
        let value = sender.text ?? ""
        if text.wrappedValue != value {
          text.wrappedValue = value
        }
      }
    }
  }

  /// Owns the UIKit responder and the accessory's SwiftUI hosting hierarchy together.
  final class KeyboardTextFieldController: UIViewController {
    let textField: KeyboardUITextField
    private(set) var selectedOptionID: String
    private var options: [KeyboardOption]
    private var accessoryController: KeyboardAccessoryController?

    init(options: [KeyboardOption], initialOption: KeyboardOption, textField: KeyboardUITextField? = nil) {
      self.options = options
      selectedOptionID = initialOption.id
      self.textField = textField ?? KeyboardUITextField()
      super.init(nibName: nil, bundle: nil)
      self.textField.keyboardType = options.first { $0.id == initialOption.id }!.keyboardType
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      textField.borderStyle = .none
      textField.textAlignment = .natural
      textField.contentHorizontalAlignment = .trailing
      textField.font = .preferredFont(forTextStyle: .body)
      textField.adjustsFontForContentSizeCategory = true
      textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
      textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      textField.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(textField)
      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        textField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        textField.topAnchor.constraint(equalTo: view.topAnchor),
        textField.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      updateAlignment()
      updateAccessory()
    }

    override func viewIsAppearing(_ animated: Bool) {
      super.viewIsAppearing(animated)
      updateAlignment()
    }

    private func updateAlignment() {
      textField.textAlignment = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .left : .right
    }

    func configureAppearance(style: UIUserInterfaceStyle, contentSizeCategory: UIContentSizeCategory) {
      overrideUserInterfaceStyle = style
      traitOverrides.preferredContentSizeCategory = contentSizeCategory
      textField.textColor = .label
      textField.font = .preferredFont(
        forTextStyle: .body,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
      )
      accessoryController?.overrideUserInterfaceStyle = style
      accessoryController?.traitOverrides.preferredContentSizeCategory = contentSizeCategory
      let appearance: UIKeyboardAppearance = style == .dark ? .dark : .light
      if textField.keyboardAppearance != appearance {
        textField.keyboardAppearance = appearance
        if textField.isFirstResponder {
          textField.reloadInputViews()
        }
      }
    }

    func configure(options: [KeyboardOption], initialOption: KeyboardOption) {
      self.options = options
      let selected = options.first { $0.id == selectedOptionID }
        ?? options.first { $0.id == initialOption.id }!
      apply(selected)
      updateAccessory()
    }

    func selectOption(id: String) {
      guard let option = options.first(where: { $0.id == id }), selectedOptionID != id else { return }
      apply(option)
      updateAccessory()
    }

    private func apply(_ option: KeyboardOption) {
      selectedOptionID = option.id
      guard textField.keyboardType != option.keyboardType else { return }
      let selection = textField.selectedTextRange
      textField.keyboardType = option.keyboardType
      if textField.isFirstResponder {
        textField.reloadInputViews()
        if let selection {
          textField.selectedTextRange = selection
        }
      }
    }

    func updateText(_ text: String) {
      // SwiftUI echoes each edit back. Reassigning it would disturb selection and IME composition.
      guard textField.text != text, textField.markedTextRange == nil else { return }
      let selection = textField.selectedTextRange.map {
        (
          textField.offset(from: textField.beginningOfDocument, to: $0.start),
          textField.offset(from: textField.beginningOfDocument, to: $0.end)
        )
      }
      textField.text = text
      if let (start, end) = selection,
         let from = textField.position(from: textField.beginningOfDocument, offset: min(start, text.utf16.count)),
         let to = textField.position(from: textField.beginningOfDocument, offset: min(end, text.utf16.count))
      {
        textField.selectedTextRange = textField.textRange(from: from, to: to)
      }
    }

    private func updateAccessory() {
      guard isViewLoaded else { return }
      guard options.count > 1 else {
        tearDownAccessory()
        return
      }
      let content = KeyboardAccessoryView(options: options, selectedID: selectedOptionID) { [weak self] id in
        self?.selectOption(id: id)
      }
      if let accessoryController {
        accessoryController.host.rootView = content
      } else {
        let accessory = KeyboardAccessoryController(content: content)
        accessory.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        accessory.traitOverrides.preferredContentSizeCategory = traitCollection.preferredContentSizeCategory
        accessory.loadViewIfNeeded()
        accessoryController = accessory
        textField.keyboardAccessory = accessory
        if textField.isFirstResponder {
          textField.reloadInputViews()
        }
      }
    }

    func tearDownAccessory() {
      guard accessoryController != nil else { return }
      textField.keyboardAccessory = nil
      accessoryController?.tearDownHost()
      accessoryController = nil
      if textField.isFirstResponder {
        textField.reloadInputViews()
      }
    }
  }

  class KeyboardUITextField: UITextField {
    var keyboardAccessory: UIInputViewController?

    override var inputAccessoryViewController: UIInputViewController? {
      keyboardAccessory
    }
  }

  /// UIKit owns this controller's keyboard-window containment. The field's controller must
  /// not parent the hosting controller itself, since its view appears in a different window.
  private final class KeyboardAccessoryController: UIInputViewController {
    let host: UIHostingController<KeyboardAccessoryView>

    init(content: KeyboardAccessoryView) {
      host = UIHostingController(rootView: content)
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
      host.view.backgroundColor = .clear
      host.safeAreaRegions = []
      host.sizingOptions = .intrinsicContentSize
      addChild(host)
      inputView = KeyboardAccessoryInputView(host: host)
      host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let size = host.sizeThatFits(in: CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude))
      if preferredContentSize != size {
        preferredContentSize = size
        view.invalidateIntrinsicContentSize()
      }
    }

    func tearDownHost() {
      host.willMove(toParent: nil)
      host.view.removeFromSuperview()
      host.removeFromParent()
    }
  }

  private final class KeyboardAccessoryInputView: UIInputView {
    private let host: UIHostingController<KeyboardAccessoryView>

    init(host: UIHostingController<KeyboardAccessoryView>) {
      self.host = host
      // Input view controllers need an initial nonzero size before the keyboard lays them out.
      super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 64), inputViewStyle: .default)
      allowsSelfSizing = true
      autoresizingMask = [.flexibleWidth]
      backgroundColor = .clear
      let hostedView = host.view!
      hostedView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(hostedView)
      NSLayoutConstraint.activate([
        hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
        hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
        hostedView.topAnchor.constraint(equalTo: topAnchor),
        hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
      let size = host.sizeThatFits(in: CGSize(width: max(bounds.width, 1), height: .greatestFiniteMagnitude))
      return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
  }

  private struct KeyboardAccessoryView: View {
    let options: [KeyboardOption]
    let selectedID: String
    let select: (String) -> Void

    var body: some View {
      HStack(spacing: 0) {
        Picker("Keyboard", selection: Binding(get: { selectedID }, set: { id in
          select(id)
        })) {
          ForEach(options) { option in
            Label(option.title, systemImage: option.systemImage)
              .tag(option.id)
          }
        }
        .labelStyle(.iconOnly)
        .pickerStyle(.segmented)
        .fixedSize()
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
      }
    }
  }
#endif

#if os(iOS)
  #Preview {
    KeyboardAccessoryView(options: [.alphabet, .numeric], selectedID: "alphabet", select: { _ in })
  }
#endif

#Preview("Independent keyboard accessories") {
  @Previewable @State var court = "12"
  @Previewable @State var division = "3"
  @Previewable @State var notes = ""
  Form {
    LabeledContent("Court") {
      KeyboardSwitchingTextField("Court", text: $court, keyboardTypes: [.alphabet, .numeric], initialKeyboardType: .numeric)
    }
    LabeledContent("Division") {
      KeyboardSwitchingTextField("Division", text: $division, keyboardTypes: [.alphabet, .numeric], initialKeyboardType: .numeric)
    }
    TextField("Ordinary input", text: $notes)
  }
}
