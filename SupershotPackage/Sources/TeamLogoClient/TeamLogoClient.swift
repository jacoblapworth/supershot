import CoreGraphics
import Dependencies
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

package nonisolated enum TeamLogoSource: Sendable {
  case data(Data)
  case file(URL)
  case photo(PhotosPickerItem)
}

package nonisolated struct PreparedTeamLogo: Equatable, Sendable {
  package var data: Data
  package var colors: [String]

  package init(data: Data, colors: [String]) {
    self.data = data
    self.colors = colors
  }
}

package nonisolated struct TeamLogoClient: Sendable {
  package var prepare: @Sendable (TeamLogoSource) async throws -> PreparedTeamLogo
  package var colors: @Sendable (Data) async throws -> [String]

  package init(
    prepare: @escaping @Sendable (TeamLogoSource) async throws -> PreparedTeamLogo,
    colors: @escaping @Sendable (Data) async throws -> [String]
  ) {
    self.prepare = prepare
    self.colors = colors
  }

  package static var live: Self {
    Self(prepare: { try await LogoProcessor.prepare($0) }, colors: {
      try await LogoProcessor.colors($0)
    })
  }
}

package extension DependencyValues {
  nonisolated var teamLogoClient: TeamLogoClient {
    get { self[TeamLogoClientKey.self] }
    set { self[TeamLogoClientKey.self] = newValue }
  }
}

private nonisolated enum TeamLogoClientKey: DependencyKey {
  static var liveValue: TeamLogoClient {
    .live
  }

  static var testValue: TeamLogoClient {
    TeamLogoClient(prepare: { _ in throw TeamLogoError.invalidImage }, colors: { _ in [] })
  }
}

package nonisolated enum TeamLogoError: Error {
  case invalidImage
}

private nonisolated enum LogoProcessor {
  @concurrent static func prepare(_ source: TeamLogoSource) async throws -> PreparedTeamLogo {
    let data: Data
    switch source {
    case let .data(value):
      data = value
    case let .file(url):
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          url.stopAccessingSecurityScopedResource()
        }
      }
      data = try Data(contentsOf: url)
    case let .photo(item):
      guard let value = try await item.loadTransferable(type: Data.self) else {
        throw TeamLogoError.invalidImage
      }
      data = value
    }
    try Task.checkCancellation()
    let image = try thumbnail(data, maximumSize: 512)
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    else { throw TeamLogoError.invalidImage }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw TeamLogoError.invalidImage }
    let normalized = output as Data
    let palette = try palette(normalized)
    try Task.checkCancellation()
    return PreparedTeamLogo(data: normalized, colors: palette)
  }

  @concurrent static func colors(_ data: Data) async throws -> [String] {
    try Task.checkCancellation()
    return try palette(data)
  }

  private static func palette(_ data: Data) throws -> [String] {
    // Sample the normalized PNG identically on import and reopening so the saved
    // colour continues to match its suggested swatch exactly.
    try extractColors(thumbnail(data, maximumSize: 512))
  }

  private static func thumbnail(_ data: Data, maximumSize: Int) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let type = CGImageSourceGetType(source),
          [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.heif.identifier].contains(type as String),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSize,
          ] as CFDictionary)
    else { throw TeamLogoError.invalidImage }
    return image
  }

  private struct Bucket {
    var count = 0
    var red = 0
    var green = 0
    var blue = 0
  }

  private static func extractColors(_ image: CGImage) -> [String] {
    // Sample at a bounded resolution in sRGB, independently of the source colour space.
    let scale = min(1, 64.0 / Double(max(image.width, image.height)))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
              data: buffer.baseAddress,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { return [] }
    var buckets: [Int: Bucket] = [:]
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Int(pixels[offset + 3])
      guard alpha >= 128 else { continue }
      let red = min(255, Int(pixels[offset]) * 255 / alpha)
      let green = min(255, Int(pixels[offset + 1]) * 255 / alpha)
      let blue = min(255, Int(pixels[offset + 2]) * 255 / alpha)
      let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
      var bucket = buckets[key, default: Bucket()]
      bucket.count += 1
      bucket.red += red
      bucket.green += green
      bucket.blue += blue
      buckets[key] = bucket
    }
    let ranked = buckets.map { key, bucket in
      let red = bucket.red / bucket.count
      let green = bucket.green / bucket.count
      let blue = bucket.blue / bucket.count
      let maximum = max(red, green, blue)
      let minimum = min(red, green, blue)
      let isColor = maximum - minimum >= 35 && maximum >= 45
      return (key: key, count: bucket.count, red: red, green: green, blue: blue, isColor: isColor)
    }.sorted {
      if $0.isColor != $1.isColor {
        return $0.isColor
      }
      if $0.count != $1.count {
        return $0.count > $1.count
      }
      return $0.key < $1.key
    }
    var selected: [(red: Int, green: Int, blue: Int)] = []
    for candidate in ranked {
      guard !selected.contains(where: {
        abs($0.red - candidate.red) + abs($0.green - candidate.green) + abs($0.blue - candidate.blue) < 80
      }) else { continue }
      selected.append((candidate.red, candidate.green, candidate.blue))
      if selected.count == 5 {
        break
      }
    }
    return selected.map { String(format: "#%02X%02X%02X", $0.red, $0.green, $0.blue) }
  }
}
