import ImageIO
import SwiftUI

/// An initials avatar with a generated background color by default.
/// Use `.backgroundStyle(_:)` to supply a color, gradient, or material.
/// Initials inherit the foreground style; use `.foregroundStyle(_:)` to customize them.
public struct AvatarView: View {
  // MARK: - Public API

  public let label: String
  public var initialsFont: Font?
  public var borderOpacity: Double
  public var logoData: Data?

  @State private var logo: CGImage?

  @Environment(\.backgroundStyle) private var backgroundStyle
  @Environment(\.controlSize) private var controlSize

  private var size: CGFloat {
    return switch controlSize {
    case .mini: 24
    case .small: 32
    case .regular: 48
    case .large: 64
    case .extraLarge: 80
    @unknown default: fatalError()
    }
  }

  // MARK: - Init

  public init(_ label: String, initialsFont: Font? = nil, borderOpacity: Double = 0.15, logoData: Data? = nil) {
    self.label = label
    self.initialsFont = initialsFont
    self.borderOpacity = borderOpacity
    self.logoData = logoData
  }

  // MARK: - Body

  public var body: some View {
    let initials = AvatarView.makeInitials(from: label)
    let bg = backgroundStyle ?? AnyShapeStyle(AvatarView.color(for: label))

    Group {
      if let logo {
        Image(decorative: logo, scale: 1)
          .resizable()
          .scaledToFit()
          .frame(width: size * 0.68, height: size * 0.68)
          .frame(width: size, height: size)
          .background(Color(white: 0.94), in: Circle())
          .accessibilityLabel(Text("Logo for \(label)"))
      } else {
        Text(initials)
          .font(initialsFont ?? .system(size: size * (initials.count > 2 ? 0.34 : 0.45), weight: .semibold, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .frame(width: size * 0.8)
          .frame(width: size, height: size)
          .background(Circle()
            .fill(bg))
          .overlay(Circle().stroke(.white.opacity(borderOpacity), lineWidth: max(1, size * 0.025)))
          .contentShape(Circle())
          .accessibilityLabel(Text(AvatarView.accessibilityLabel(for: label, initials: initials)))
      }
    }
    .task(id: logoData) {
      guard logoData != nil else {
        logo = nil
        return
      }
      let decoded = await Self.decodeLogo(logoData)
      guard !Task.isCancelled else { return }
      logo = decoded
    }
  }

  @concurrent private static func decodeLogo(_ data: Data?) async -> CGImage? {
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 512,
    ] as CFDictionary)
  }
}

// MARK: - Helpers

public extension AvatarView {
  /// Produces up to three initials, skipping common function words unless no others remain.
  /// Preserves single-word uppercase acronyms, truncated to three characters.
  static func makeInitials(from label: String) -> String {
    let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let parts = label.components(separatedBy: separators).filter { !$0.isEmpty }
    guard !parts.isEmpty else { return "?" }

    let ignoredWords: Set = ["a", "an", "the", "of", "and", "for", "in", "on", "at", "to", "&"]
    let meaningfulWords = parts.filter { !ignoredWords.contains($0.lowercased()) }
    let words = meaningfulWords.isEmpty ? parts : meaningfulWords

    if parts.count == 1, let word = meaningfulWords.first,
       word.allSatisfy(\.isLetter), word == word.uppercased(), word != word.lowercased()
    {
      return String(word.prefix(3))
    }

    return String(String(words.prefix(3).compactMap(\.first)).uppercased().prefix(3))
  }

  /// Deterministically maps a string to a pleasant, varied color.
  static func color(for label: String) -> Color {
    // Simple FNV-1a 32-bit hash for stability across runs
    let bytes = Array(label.utf8)
    var hash: UInt32 = 0x811C_9DC5
    for b in bytes {
      hash ^= UInt32(b)
      hash = hash &* 16_777_619
    }
    // Map hash into H, S, B ranges for visually distinct colors
    let hue = Double(hash % 360) / 360.0
    let saturation = 0.55 + Double((hash >> 8) % 30) / 100.0 // 0.55 - 0.85
    let brightness = 0.70 + Double((hash >> 16) % 20) / 100.0 // 0.70 - 0.90
    return Color(
      hue: hue,
      saturation: min(max(saturation, 0.0), 1.0),
      brightness: min(max(brightness, 0.0), 1.0)
    )
  }

  /// Accessibility phrase, e.g., "Avatar for Ada Lovelace, initials AL".
  static func accessibilityLabel(for label: String, initials: String) -> String {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "Avatar with placeholder"
    }
    return "Avatar for \(trimmed), initials \(initials)"
  }
}

#Preview("AvatarView") {
  VStack(spacing: 16) {
    AvatarView("Ada Lovelace")
      .foregroundStyle(.white)
    AvatarView("Material")
      .backgroundStyle(.thinMaterial)
      .foregroundStyle(.primary)
    AvatarView("Gradient")
      .backgroundStyle(.blue.gradient)
      .foregroundStyle(.white)
    AvatarView("Foreground")
      .backgroundStyle(.thinMaterial)
      .foregroundStyle(.purple.gradient)
    AvatarView("grace hopper")
      .controlSize(.small)
    AvatarView("single")
      .controlSize(.mini)
    AvatarView("")
      .controlSize(.large)
    AvatarView("😀 Emoji User")
      .controlSize(.extraLarge)
    HStack {
      ForEach(["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank"], id: \.self) { name in
        AvatarView(name)
      }
    }
  }
  .padding()
}
