import SwiftUI

/// An initials avatar with a generated background color by default.
/// Use `.backgroundStyle(_:)` to supply a color, gradient, or material.
/// Initials inherit the foreground style; use `.foregroundStyle(_:)` to customize them.
public struct AvatarView: View {
  // MARK: - Public API

  public let label: String

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

  public init(_ label: String) {
    self.label = label
  }

  // MARK: - Body

  public var body: some View {
    let initials = AvatarView.makeInitials(from: label)
    let bg = backgroundStyle ?? AnyShapeStyle(AvatarView.color(for: label))

    Text(initials)
      .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
      .minimumScaleFactor(0.5)
      .frame(width: size, height: size)
      .background(Circle()
        .fill(bg))
      .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: max(1, size * 0.025)))
      .contentShape(Circle())
      .accessibilityLabel(Text(AvatarView.accessibilityLabel(for: label, initials: initials)))
  }
}

// MARK: - Helpers

public extension AvatarView {
  /// Produces up to two-letter initials from a label, e.g., "Ada Lovelace" -> "AL".
  /// Handles single words, multi-words, extra whitespace, emojis, and empty strings.
  static func makeInitials(from label: String) -> String {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "?"
    }

    // Split by whitespace and punctuation commonly separating names/words
    let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let parts =
      trimmed
        .components(separatedBy: separators)
        .filter { !$0.isEmpty }

    if parts.isEmpty {
      return "?"
    }

    // Take first character from first two parts when possible, else from first part only
    var chars: [Character] = []
    if let first = parts.first?.first {
      chars.append(first)
    }
    if parts.count > 1, let second = parts[1].first {
      chars.append(second)
    }

    // Uppercased string for letters; non-alphabetics will remain as-is when uppercased
    return String(chars).uppercased()
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
