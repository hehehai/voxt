import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Voxt

final class TranscriptionAppContextSupportTests: XCTestCase {
    func testMakeImageAttachmentDownscalesAndCompressesLargeImages() throws {
        let imageData = try makePNGData(width: 2200, height: 1500)

        let attachment = try XCTUnwrap(
            TranscriptionAppContextCaptureService.makeImageAttachment(
                from: imageData,
                appName: "  My App  "
            )
        )
        let outputImage = try XCTUnwrap(decodeImage(from: attachment.data))

        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertEqual(attachment.filename, "My-App-context.jpg")
        XCTAssertNotEqual(attachment.detail, .high)
        XCTAssertLessThanOrEqual(
            max(outputImage.width, outputImage.height),
            TranscriptionAppContextCaptureService.preferredImageAttachmentLongEdge
        )
        XCTAssertLessThanOrEqual(
            attachment.data.count,
            TranscriptionAppContextCaptureService.maxImageAttachmentBytes
        )
    }

    func testMakeImageAttachmentDoesNotUpscaleSmallImages() throws {
        let imageData = try makePNGData(width: 800, height: 600)

        let attachment = try XCTUnwrap(
            TranscriptionAppContextCaptureService.makeImageAttachment(
                from: imageData,
                appName: "Mini"
            )
        )
        let outputImage = try XCTUnwrap(decodeImage(from: attachment.data))

        XCTAssertEqual(outputImage.width, 800)
        XCTAssertEqual(outputImage.height, 600)
        XCTAssertEqual(attachment.detail, .low)
    }

    private func decodeImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = Data(count: height * bytesPerRow)
        var state: UInt64 = 0x1234_5678_9ABC_DEF0

        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

            for y in 0 ..< height {
                for x in 0 ..< width {
                    state = state &* 6364136223846793005 &+ 1
                    let offset = y * bytesPerRow + x * bytesPerPixel
                    bytes[offset] = UInt8(truncatingIfNeeded: state >> 24)
                    bytes[offset + 1] = UInt8((x * 37 + y * 17) & 0xFF)
                    bytes[offset + 2] = UInt8(truncatingIfNeeded: state >> 40)
                    bytes[offset + 3] = 255
                }
            }
        }

        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            XCTFail("Failed to create source image for test.")
            return Data()
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            XCTFail("Failed to create PNG destination for test.")
            return Data()
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
