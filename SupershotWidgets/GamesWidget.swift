import Foundation
import SwiftUI
import UI
import WidgetKit
import WidgetSupport

struct GamesEntry: TimelineEntry {
  var date: Date
  var games: [WidgetGame]
  var unavailable = false
}

struct GamesProvider: TimelineProvider {
  func placeholder(in _: Context) -> GamesEntry {
    .example
  }

  func getSnapshot(in context: Context, completion: @escaping (GamesEntry) -> Void) {
    if context.isPreview {
      completion(.example)
    } else {
      completion(entry(at: .now))
    }
  }

  func getTimeline(in _: Context, completion: @escaping (Timeline<GamesEntry>) -> Void) {
    let now = Date.now
    do {
      let games = try GamesWidgetStore.read()
      // Bound the timeline; the next request continues from the same durable snapshot.
      let dates = [now] + GamesWidgetSelection.transitionDates(games, after: now).prefix(64)
      completion(Timeline(entries: dates.map {
        GamesEntry(date: $0, games: GamesWidgetSelection.games(games, at: $0))
      }, policy: dates.count > 1 ? .atEnd : .after(now.addingTimeInterval(60 * 60))))
    } catch {
      completion(Timeline(entries: [GamesEntry(date: now, games: [], unavailable: true)],
                          policy: .after(now.addingTimeInterval(15 * 60))))
    }
  }

  private func entry(at date: Date) -> GamesEntry {
    do {
      return try GamesEntry(date: date, games: GamesWidgetSelection.games(GamesWidgetStore.read(), at: date))
    } catch {
      return GamesEntry(date: date, games: [], unavailable: true)
    }
  }
}

struct GamesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: GamesWidgetStore.kind, provider: GamesProvider()) { entry in
      GamesWidgetView(entry: entry)
        .containerBackground(.background, for: .widget)
    }
    .configurationDisplayName("Games")
    .description("Upcoming games first, then games in progress and results from the last seven days. Scores update periodically.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    .contentMarginsDisabled()
  }
}

struct GamesWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @ScaledMetric(relativeTo: .caption) private var minimumRowHeight: CGFloat = 72
  var entry: GamesEntry

  var body: some View {
    if let game = entry.games.first {
      if family == .systemSmall {
        GameCardView(game: game, compact: true, featured: true)
          .dynamicTypeSize(...DynamicTypeSize.large)
          .widgetURL(GamesWidgetStore.gameURL(game.id))
      } else {
        GeometryReader { geometry in
          let columns = family == .systemExtraLarge ? 2 : 1
          let minimumHeight = minimumRowHeight
          let rows = min(family == .systemMedium ? 2 : 4,
                         max(1, Int((geometry.size.height - 16 + 6) / (minimumHeight + 6))))
          let capacity = min(rows * columns, family == .systemMedium ? 2 : columns * 4)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(entry.games.prefix(capacity)) { game in
              Link(destination: GamesWidgetStore.gameURL(game.id)) {
                GameCardView(game: game, compact: true)
                  .frame(height: max(minimumHeight, (geometry.size.height - 16 - CGFloat(rows - 1) * 6) / CGFloat(rows)))
                  .background(Color.clear)
                  .clipShape(.rect(cornerRadius: 14))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(8)
        }
      }
    } else {
      Link(destination: GamesWidgetStore.newGameURL) {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: entry.unavailable ? "sportscourt" : "plus.circle.fill")
            .font(.title).widgetAccentable()
          Text(entry.unavailable ? "Open Supershot" : "No games yet").font(.headline)
          Text(entry.unavailable ? "Open the app to load your games." : "Plan your next game.")
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
      }
      .buttonStyle(.plain)
      .widgetURL(GamesWidgetStore.newGameURL)
    }
  }
}

extension GamesEntry {
  static var example: Self {
    let now = Date.now
    let games: [WidgetGame] = (0 ..< 8).map { (index: Int) -> WidgetGame in
      let scheduled = now.addingTimeInterval(Double(index + 1) * 3600)
      return WidgetGame(id: UUID(), createdAt: now, scheduledAt: scheduled,
                        startedAt: (index == 1 || index == 2) ? now : nil, endedAt: index == 2 ? now : nil,
                        teamAName: index == 0 ? "Thunder" : "Swifts", teamAColorHex: "#007AFF", teamAScore: 42,
                        teamBName: "Lightning", teamBColorHex: "#FF3B30", teamBScore: 38)
    }
    return Self(date: now, games: games)
  }
}

#Preview(as: .systemSmall) { GamesWidget() } timeline: { GamesEntry.example }
#Preview(as: .systemMedium) { GamesWidget() } timeline: { GamesEntry.example }
#Preview(as: .systemLarge) { GamesWidget() } timeline: { GamesEntry.example }
#Preview(as: .systemExtraLarge) { GamesWidget() } timeline: { GamesEntry.example }
