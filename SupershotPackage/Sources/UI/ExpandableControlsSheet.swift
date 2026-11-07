import SwiftUI
#if os(iOS)
  import UIKit
#endif

#if os(iOS)
  /// A persistent sheet with a measured, pinned header and scrollable controls.
  /// The reveal key changes only when an action should be brought into view.
  package struct ExpandableControlsSheet<Reveal: Equatable, Scoring: View, Primary: View, Additional: View>: View {
    package var reveal: Reveal?
    package var collapseTrigger: Int
    package var onFrameChange: (CGRect) -> Void
    @ViewBuilder package var scoring: () -> Scoring
    @ViewBuilder package var primary: () -> Primary
    @ViewBuilder package var additional: () -> Additional

    @State private var heights = ControlsSheetHeights()
    @State private var isCollapsed = true
    @State private var revealRevision = 0

    package init(
      reveal: Reveal?,
      collapseTrigger: Int = 0,
      onFrameChange: @escaping (CGRect) -> Void,
      @ViewBuilder scoring: @escaping () -> Scoring,
      @ViewBuilder primary: @escaping () -> Primary,
      @ViewBuilder additional: @escaping () -> Additional
    ) {
      self.reveal = reveal
      self.collapseTrigger = collapseTrigger
      self.onFrameChange = onFrameChange
      self.scoring = scoring
      self.primary = primary
      self.additional = additional
    }

    package var body: some View {
      GeometryReader { geometry in
        let lowerMinimum = isCollapsed
          ? 0
          : min(max(heights.primary, 60), geometry.size.height / 2)
        VStack(spacing: 0) {
          // In an exceptionally short viewport the scoring region itself must remain reachable.
          ScrollView {
            scoring()
              .frame(maxWidth: .infinity)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 16)
              .padding(.top, 24)
              .padding(.bottom, 16)
              .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: {
                heights.scoring = $0
              }
          }
          .scrollBounceBehavior(.basedOnSize)
          .frame(height: min(heights.scoring, max(0, geometry.size.height - lowerMinimum)))

          ScrollViewReader { proxy in
            ScrollView {
              VStack(spacing: 16) {
                if reveal != nil {
                  primary()
                    .id("primary")
                    .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: {
                      heights.primary = $0 + 16
                    }
                }
                additional()
              }
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 16)
              .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: reveal, initial: true) { _, current in
              if current != nil {
                revealRevision += 1
                proxy.scrollTo("primary", anchor: .top)
              }
            }
          }
          .frame(maxHeight: .infinity)
        }
      }
      .clipped()
      .background {
        ControlsSheetPresentation(
          heights: heights,
          hasPrimary: reveal != nil,
          revealRevision: revealRevision,
          onMetrics: { frame, collapsed in
            onFrameChange(frame)
            isCollapsed = collapsed
          }
        )
      }
      .presentationSizing(.page)
      .presentationCompactAdaptation(.sheet)
      .presentationBackgroundInteraction(.enabled)
      .presentationDragIndicator(.visible)
      .interactiveDismissDisabled()
      .onChange(of: collapseTrigger) { _, _ in revealRevision += 1 }
    }
  }

  private struct ControlsSheetHeights: Equatable {
    var scoring: CGFloat = 1
    var primary: CGFloat = 0
  }

  /// UIKit resolves the cap against the real medium detent and explicitly refreshes
  /// custom detents when SwiftUI's measured content changes.
  private struct ControlsSheetPresentation: UIViewControllerRepresentable {
    var heights: ControlsSheetHeights
    var hasPrimary: Bool
    var revealRevision: Int
    var onMetrics: (CGRect, Bool) -> Void

    func makeUIViewController(context _: Context) -> ControlsSheetController {
      ControlsSheetController()
    }

    func updateUIViewController(_ controller: ControlsSheetController, context _: Context) {
      controller.onMetrics = onMetrics
      controller.update(heights: heights, hasPrimary: hasPrimary, revision: revealRevision)
    }

    static func dismantleUIViewController(_ controller: ControlsSheetController, coordinator _: ()) {
      controller.stopObserving()
    }
  }

  private final class ControlsSheetController: UIViewController {
    private static let scoringID = UISheetPresentationController.Detent.Identifier("controls.scoring")
    private static let primaryID = UISheetPresentationController.Detent.Identifier("controls.primary")
    private static let maximumID = UISheetPresentationController.Detent.Identifier("controls.maximum")
    private var heights = ControlsSheetHeights()
    private var hasPrimary = false
    private var revision = 0
    private var appliedHeights: ControlsSheetHeights?
    private var appliedPrimary: Bool?
    private var appliedRevision: Int?
    private weak var sheet: UISheetPresentationController?
    private var displayLink: CADisplayLink?
    private var lastFrame = CGRect.zero
    private var lastCollapsed: Bool?
    var onMetrics: (CGRect, Bool) -> Void = { _, _ in }

    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      connectToSheet()
      apply()
    }

    private func connectToSheet() {
      var ancestor = parent
      while let controller = ancestor {
        if let sheet = controller.presentationController as? UISheetPresentationController {
          if self.sheet !== sheet {
            appliedHeights = nil
            appliedPrimary = nil
            appliedRevision = nil
            lastCollapsed = nil
          }
          self.sheet = sheet
          break
        }
        ancestor = controller.parent
      }
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      connectToSheet()
      apply()
      stopObserving()
      let link = CADisplayLink(target: self, selector: #selector(sampleFrame))
      link.add(to: .main, forMode: .common)
      displayLink = link
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      stopObserving()
    }

    func stopObserving() {
      displayLink?.invalidate()
      displayLink = nil
    }

    func update(heights: ControlsSheetHeights, hasPrimary: Bool, revision: Int) {
      self.heights = heights
      self.hasPrimary = hasPrimary
      self.revision = revision
      apply()
    }

    private static func maximum(in context: any UISheetPresentationControllerDetentResolutionContext) -> CGFloat {
      let medium = UISheetPresentationController.Detent.medium().resolvedValue(in: context)
      return medium ?? context.maximumDetentValue / 2
    }

    private func apply() {
      guard let sheet,
            heights != appliedHeights || hasPrimary != appliedPrimary || revision != appliedRevision
      else { return }
      let shouldSelect = appliedRevision != revision
      let shouldReplaceDetents = appliedPrimary != hasPrimary
      appliedHeights = heights
      appliedPrimary = hasPrimary
      appliedRevision = revision
      sheet.animateChanges {
        if shouldReplaceDetents {
          var detents: [UISheetPresentationController.Detent] = [
            .custom(identifier: Self.scoringID) { [weak self] context in
              min(self?.heights.scoring ?? 1, Self.maximum(in: context))
            },
          ]
          if hasPrimary {
            detents.append(.custom(identifier: Self.primaryID) { [weak self] context in
              guard let self else { return 1 }
              return min(heights.scoring + heights.primary, Self.maximum(in: context))
            })
          }
          detents.append(.custom(identifier: Self.maximumID) { Self.maximum(in: $0) })
          sheet.detents = detents
          sheet.largestUndimmedDetentIdentifier = Self.maximumID
        }
        if shouldSelect {
          sheet.selectedDetentIdentifier = hasPrimary ? Self.primaryID : Self.scoringID
        } else if !hasPrimary, sheet.selectedDetentIdentifier == Self.primaryID {
          sheet.selectedDetentIdentifier = Self.scoringID
        }
        sheet.invalidateDetents()
      }
    }

    @objc private func sampleFrame() {
      guard let sheet, let window = view.window
      else { return }
      // Presentation-layer geometry follows an interactive drag and its settling animation.
      // Measure our content view: the presentation controller's presentedView can be
      // a full-height wrapper whose clipped child owns the visible sheet position.
      let frame: CGRect = if let layer = view.layer.presentation(), let windowLayer = window.layer.presentation() {
        layer.convert(layer.bounds, to: windowLayer).integral
      } else {
        view.convert(view.bounds, to: window).integral
      }
      let collapsed = sheet.selectedDetentIdentifier == Self.scoringID
      guard frame != lastFrame || collapsed != lastCollapsed else { return }
      lastFrame = frame
      lastCollapsed = collapsed
      onMetrics(frame, collapsed)
    }
  }

  #Preview("Taller scoring controls") {
    @Previewable @State var presented = true
    Color.blue.opacity(0.2)
      .sheet(isPresented: $presented) {
        ExpandableControlsSheet(reveal: String?.none, onFrameChange: { _ in }) {
          HStack {
            ForEach(["Team A", "Team B"], id: \.self) { team in
              VStack {
                Button("1 point · \(team)") {}
                Button("2 points · \(team)") {}
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.extraLarge)
            }
          }
        } primary: {
          EmptyView()
        } additional: {
          ForEach(0 ..< 12) { index in
            Button("Additional control \(index + 1)") {}
          }
        }
      }
  }
#endif
