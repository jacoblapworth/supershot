import CoreGraphics
import CustomDump
import Foundation
import ImageIO
import TeamLogoClient
import Testing
import TestSupport
import UniformTypeIdentifiers

extension SupershotTestSuite {
  struct TeamLogoClientTests {
    @Test
    func normalizesLargeImagesAndPreservesTransparency() async throws {
      let data = try logoImage(width: 1200, height: 600) { x, _ in
        x < 600 ? (255, 0, 0, 255) : (0, 0, 0, 0)
      }
      let logo = try await TeamLogoClient.live.prepare(.data(data))
      let source = try #require(CGImageSourceCreateWithData(logo.data as CFData, nil))
      let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      expectNoDifference(image.width, 512)
      expectNoDifference(image.height, 256)
      expectNoDifference(CGImageSourceGetType(source) as String?, UTType.png.identifier)
      #expect(image.alphaInfo != .none)
      let colour = try #require(logo.colors.first)
      let rgb = try #require(UInt32(colour.dropFirst(), radix: 16))
      // Resampling a transparent edge can shift the averaged red channel slightly.
      #expect(rgb >> 16 >= 250)
      expectNoDifference(rgb & 0xFFFF, 0)
    }

    @Test
    func smallImagesAreNotUpscaledAndPaletteIsDeterministic() async throws {
      let data = try logoImage(width: 20, height: 10) { x, _ in
        x < 16 ? (255, 255, 255, 255) : (0, 102, 204, 255)
      }
      let logo = try await TeamLogoClient.live.prepare(.data(data))
      let repeated = try await TeamLogoClient.live.prepare(.data(data))
      expectNoDifference(logo, repeated)
      expectNoDifference(logo.colors.first, "#0066CC")
      let palette = try await TeamLogoClient.live.colors(logo.data)
      expectNoDifference(palette, logo.colors)
      let source = try #require(CGImageSourceCreateWithData(logo.data as CFData, nil))
      let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      expectNoDifference(image.width, 20)
      expectNoDifference(image.height, 10)
    }

    @Test
    func transparentImagesHaveNoSuggestedColour() async throws {
      let data = try logoImage { _, _ in (0, 0, 0, 0) }
      let logo = try await TeamLogoClient.live.prepare(.data(data))
      expectNoDifference(logo.colors, [])
    }

    @Test
    func downsampledLogoKeepsIdenticalSwatchesWhenReopened() async throws {
      let data = try logoImage(width: 640, height: 800) { x, y in
        if x < 35 || x > 605 || y < 25 || y > 775 {
          return (0, 0, 0, 0)
        }
        if y < 520 {
          return (0, 102, 204, 255)
        }
        return x < 320 ? (255, 204, 0, 255) : (255, 255, 255, 255)
      }
      let imported = try await TeamLogoClient.live.prepare(.data(data))
      let reopened = try await TeamLogoClient.live.colors(imported.data)
      expectNoDifference(reopened, imported.colors)
      #expect(!reopened.isEmpty)
    }

    @Test
    func monochromeLogoOffersNeutralColour() async throws {
      let data = try logoImage { _, _ in (34, 34, 34, 255) }
      let logo = try await TeamLogoClient.live.prepare(.data(data))
      expectNoDifference(logo.colors, ["#222222"])
    }

    @Test
    func correctsJPEGOrientationAndStripsMetadata() async throws {
      let data = try logoImage(width: 40, height: 20, type: .jpeg, properties: [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private source metadata"],
      ]) { _, _ in (255, 0, 0, 255) }
      let originalSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
      let originalProperties = try #require(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any])
      let originalExif = try #require(originalProperties[kCGImagePropertyExifDictionary] as? [CFString: Any])
      #expect(originalExif[kCGImagePropertyExifUserComment] != nil)
      let logo = try await TeamLogoClient.live.prepare(.data(data))
      let source = try #require(CGImageSourceCreateWithData(logo.data as CFData, nil))
      let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      expectNoDifference(image.width, 20)
      expectNoDifference(image.height, 40)
      let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
      let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
      #expect(exif?[kCGImagePropertyExifUserComment] == nil)
      #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test
    func loadsImageFile() async throws {
      let data = try logoImage { _, _ in (0, 255, 0, 255) }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
      try data.write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }
      let logo = try await TeamLogoClient.live.prepare(.file(url))
      expectNoDifference(logo.colors.first, "#00FF00")
    }

    @Test
    func rejectsInvalidAndUnsupportedImages() async throws {
      await #expect(throws: (any Error).self) {
        try await TeamLogoClient.live.prepare(.data(Data("not an image".utf8)))
      }
      let gif = try logoImage(type: .gif) { _, _ in (255, 0, 0, 255) }
      await #expect(throws: (any Error).self) {
        try await TeamLogoClient.live.prepare(.data(gif))
      }
    }
  }
}

private nonisolated func logoImage(
  width: Int = 16,
  height: Int = 16,
  type: UTType = .png,
  properties: [CFString: Any] = [:],
  pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
) throws -> Data {
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  for y in 0 ..< height {
    for x in 0 ..< width {
      let (r, g, b, a) = pixel(x, y)
      let offset = (y * width + x) * 4
      pixels[offset] = r
      pixels[offset + 1] = g
      pixels[offset + 2] = b
      pixels[offset + 3] = a
    }
  }
  let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
  let image = try #require(CGImage(
    width: width,
    height: height,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
  ))
  let data = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, properties as CFDictionary)
  try #require(CGImageDestinationFinalize(destination))
  return data as Data
}
