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
      completion(Timeline(
        entries: [GamesEntry(date: now, games: [], unavailable: true)],
        policy: .after(now.addingTimeInterval(15 * 60))
      ))
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
  @ScaledMetric(relativeTo: .caption) private var minimumRowHeight: CGFloat = 64
  var entry: GamesEntry

  var body: some View {
    if let game = entry.games.first {
      if family == .systemSmall {
        GameRow(widgetGame: game, layout: .stacked)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(8)
          .dynamicTypeSize(...DynamicTypeSize.large)
          .widgetURL(GamesWidgetStore.gameURL(game.id))
      } else {
        gameGrid
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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

  private var gameGrid: some View {
    GeometryReader { geometry in
      let columns = family == .systemExtraLarge ? 2 : 1
      let maximumRows = family == .systemMedium ? 2 : 4
      let availableHeight = max(0, geometry.size.height - 16)
      let dividerHeight: CGFloat = 6
      let fittingRows = min(maximumRows, max(1, Int((availableHeight + dividerHeight) / (minimumRowHeight + dividerHeight))))
      let games = Array(entry.games.prefix(fittingRows * columns))
      let rowCount = (games.count + columns - 1) / columns
      let rowHeight = (availableHeight - CGFloat(fittingRows - 1) * dividerHeight) / CGFloat(fittingRows)

      VStack(spacing: 0) {
        ForEach(0 ..< rowCount, id: \.self) { row in
          if row > 0 {
            Divider()
              .frame(height: dividerHeight)
              .accessibilityHidden(true)
          }
          HStack(spacing: 6) {
            ForEach(0 ..< columns, id: \.self) { column in
              let index = row * columns + column
              if index < games.count {
                let game = games[index]
                Link(destination: GamesWidgetStore.gameURL(game.id)) {
                  GameRow(widgetGame: game, layout: .compact)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
              } else {
                Color.clear.frame(maxWidth: .infinity)
              }
            }
          }
          .frame(height: rowHeight)
        }
      }
      .padding(8)
    }
  }
}

extension GamesEntry {
  static var example: Self {
    let now = Date.now
    let games: [WidgetGame] = (0 ..< 8).map { (index: Int) -> WidgetGame in
      let scheduled = now.addingTimeInterval(Double(index + 1) * 3600)
      return WidgetGame(
        id: UUID(),
        createdAt: now,
        scheduledAt: scheduled,
        startedAt: (index == 1 || index == 2) ? now : nil,
        endedAt: index == 2 ? now : nil,
        teamAName: index == 0 ? "Thunder" : "Swifts",
        teamAColorHex: "#007AFF",
        teamAScore: 42,
        teamBName: "Lightning",
        teamBColorHex: "#FF3B30",
        teamBScore: 38
      )
    }
    return Self(date: now, games: games)
  }
}

#Preview(as: .systemSmall) { GamesWidget() } timeline: { GamesEntry.example }
#Preview(as: .systemMedium) { GamesWidget() } timeline: { GamesEntry.example }
#Preview(as: .systemLarge) { GamesWidget() } timeline: { GamesEntry.example }
#Preview(as: .systemExtraLarge) { GamesWidget() } timeline: { GamesEntry.example }
