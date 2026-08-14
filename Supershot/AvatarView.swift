import SwiftUI

public struct AvatarView: View {
    // MARK: - Public API
    public let label: String
    public var size: CGFloat
    public var backgroundColor: Color?

    // MARK: - Init
    public init(label: String, size: CGFloat = 40, backgroundColor: Color? = nil) {
        self.label = label
        self.size = size
        self.backgroundColor = backgroundColor
    }

    // MARK: - Body
    public var body: some View {
        let initials = AvatarView.makeInitials(from: label)
        let bg = backgroundColor ?? AvatarView.color(for: label)

        Text(initials)
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(bg.gradient)
            )
            .overlay(
                Circle().stroke(.white.opacity(0.15), lineWidth: max(1, size * 0.025))
            )
            .contentShape(Circle())
            .accessibilityLabel(Text(AvatarView.accessibilityLabel(for: label, initials: initials)))
    }
}

// MARK: - Helpers
extension AvatarView {
    /// Produces up to two-letter initials from a label, e.g., "Ada Lovelace" -> "AL".
    /// Handles single words, multi-words, extra whitespace, emojis, and empty strings.
    static func makeInitials(from label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }

        // Split by whitespace and punctuation commonly separating names/words
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let parts = trimmed
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        if parts.isEmpty { return "?" }

        // Take first character from first two parts when possible, else from first part only
        var chars: [Character] = []
        if let first = parts.first?.first { chars.append(first) }
        if parts.count > 1, let second = parts[1].first { chars.append(second) }

        // Uppercased string for letters; non-alphabetics will remain as-is when uppercased
        return String(chars).uppercased()
    }

    /// Deterministically maps a string to a pleasant, varied color.
    static func color(for label: String) -> Color {
        // Simple FNV-1a 32-bit hash for stability across runs
        let bytes = Array(label.utf8)
        var hash: UInt32 = 0x811C9DC5
        for b in bytes {
            hash ^= UInt32(b)
            hash = hash &* 16777619
        }
        // Map hash into H, S, B ranges for visually distinct colors
        let hue = Double((hash % 360)) / 360.0
        let saturation = 0.55 + Double((hash >> 8) % 30) / 100.0 // 0.55 - 0.85
        let brightness = 0.70 + Double((hash >> 16) % 20) / 100.0 // 0.70 - 0.90
        return Color(hue: hue, saturation: min(max(saturation, 0.0), 1.0), brightness: min(max(brightness, 0.0), 1.0))
    }

    /// Accessibility phrase, e.g., "Avatar for Ada Lovelace, initials AL".
    static func accessibilityLabel(for label: String, initials: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Avatar with placeholder" }
        return "Avatar for \(trimmed), initials \(initials)"
    }
}

#Preview("AvatarView") {
    VStack(spacing: 16) {
        AvatarView(label: "Ada Lovelace")
        AvatarView(label: "grace hopper", size: 56)
        AvatarView(label: "single", size: 48)
        AvatarView(label: "", size: 40)
        AvatarView(label: "😀 Emoji User", size: 44)
        HStack {
            ForEach(["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank"], id: \.self) { name in
                AvatarView(label: name, size: 36)
            }
        }
    }
    .padding()
}
