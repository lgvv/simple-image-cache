import Foundation
@testable import ImageCache
import ImageIO
import Testing

import UIKit

// MARK: - DownsamplingImageDecoder Tests

@Suite
struct DownsamplingImageDecoderTests {
    @Test("빈 데이터는 emptyData 에러 발생")
    func throwsEmptyDataForEmptyInput() {
        // Given
        let sut = DownsamplingImageDecoder(targetSize: CGSize(width: 50, height: 50))

        // When / Then
        #expect {
            try sut.decode(Data())
        } throws: { error in
            guard let e = error as? ImageCacheError, case .emptyData = e else { return false }
            return true
        }
    }

    @Test("유효하지 않은 데이터는 invalidImageData 에러 발생")
    func throwsInvalidImageDataForInvalidInput() {
        // Given
        let sut = DownsamplingImageDecoder(targetSize: CGSize(width: 50, height: 50))

        // When / Then
        #expect {
            try sut.decode(Data([0x00, 0x01, 0x02]))
        } throws: { error in
            guard let e = error as? ImageCacheError, case .invalidImageData = e else { return false }
            return true
        }
    }

    @Test("scaleAspectFit: 출력 이미지 크기가 targetSize 이하")
    func fitsOutputWithinTargetSizeForAspectFit() throws {
        // Given
        let data = makePNGData(width: 200, height: 100)
        let targetSize = CGSize(width: 50, height: 50)
        let sut = DownsamplingImageDecoder(
            targetSize: targetSize,
            scale: 1.0,
            contentMode: .scaleAspectFit
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(image.size.width <= targetSize.width + 1)
        #expect(image.size.height <= targetSize.height + 1)
    }

    @Test("scaleAspectFill: 출력 이미지 크기가 정확히 targetSize")
    func matchesTargetSizeForAspectFill() throws {
        // Given
        let data = makePNGData(width: 200, height: 100)
        let targetSize = CGSize(width: 50, height: 50)
        let sut = DownsamplingImageDecoder(
            targetSize: targetSize,
            scale: 1.0,
            contentMode: .scaleAspectFill
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(abs(image.size.width - targetSize.width) < 1)
        #expect(abs(image.size.height - targetSize.height) < 1)
    }

    @Test("scaleToFill: 출력 이미지 크기가 정확히 targetSize")
    func matchesTargetSizeForScaleToFill() throws {
        // Given
        let data = makePNGData(width: 200, height: 100)
        let targetSize = CGSize(width: 50, height: 50)
        let sut = DownsamplingImageDecoder(
            targetSize: targetSize,
            scale: 1.0,
            contentMode: .scaleToFill
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(abs(image.size.width - targetSize.width) < 1)
        #expect(abs(image.size.height - targetSize.height) < 1)
    }
}

// MARK: - ResizingImageDecoder Tests

@Suite struct ResizingImageDecoderTests {
    @Test("빈 데이터는 emptyData 에러 발생")
    func throwsEmptyDataForEmptyInput() {
        // Given
        let sut = ResizingImageDecoder(targetSize: CGSize(width: 50, height: 50))

        // When / Then
        #expect {
            try sut.decode(Data())
        } throws: { error in
            guard let e = error as? ImageCacheError, case .emptyData = e else { return false }
            return true
        }
    }

    @Test("유효하지 않은 데이터는 invalidImageData 에러 발생")
    func throwsInvalidImageDataForInvalidInput() {
        // Given
        let sut = ResizingImageDecoder(targetSize: CGSize(width: 50, height: 50))

        // When / Then
        #expect {
            try sut.decode(Data([0x00, 0x01, 0x02]))
        } throws: { error in
            guard let e = error as? ImageCacheError, case .invalidImageData = e else { return false }
            return true
        }
    }

    @Test("scaleAspectFit: 출력 이미지 크기가 targetSize 이하")
    func fitsOutputWithinTargetSizeForAspectFit() throws {
        // Given
        let data = makePNGData(width: 200, height: 100)
        let targetSize = CGSize(width: 50, height: 50)
        let sut = ResizingImageDecoder(
            targetSize: targetSize,
            scale: 1.0,
            contentMode: .scaleAspectFit
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(image.size.width <= targetSize.width + 1)
        #expect(image.size.height <= targetSize.height + 1)
    }

    @Test("scaleAspectFill: 출력 이미지 크기가 정확히 targetSize")
    func matchesTargetSizeForAspectFill() throws {
        // Given
        let data = makePNGData(width: 200, height: 100)
        let targetSize = CGSize(width: 50, height: 50)
        let sut = ResizingImageDecoder(
            targetSize: targetSize,
            scale: 1.0,
            contentMode: .scaleAspectFill
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(abs(image.size.width - targetSize.width) < 1)
        #expect(abs(image.size.height - targetSize.height) < 1)
    }

    @Test("scaleToFill: 출력 이미지 크기가 정확히 targetSize")
    func matchesTargetSizeForScaleToFill() throws {
        // Given
        let data = makePNGData(width: 200, height: 100)
        let targetSize = CGSize(width: 50, height: 50)
        let sut = ResizingImageDecoder(
            targetSize: targetSize,
            scale: 1.0,
            contentMode: .scaleToFill
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(abs(image.size.width - targetSize.width) < 1)
        #expect(abs(image.size.height - targetSize.height) < 1)
    }
}

// MARK: - UIImageDecoder Tests

@Suite struct UIImageDecoderTests {
    @Test("애니메이션 데이터는 animated UIImage로 디코딩")
    func decodesAnimatedImageFromAnimatedData() throws {
        // Given
        let data = makeAnimatedGIFData(width: 60, height: 40, frameCount: 3, frameDuration: 0.08)
        let sut = UIImageDecoder()

        // When
        let image = try sut.decode(data)

        // Then
        #expect(image.images?.count == 3)
        #expect(image.duration >= 0.2)
    }
}

// MARK: - DownsamplingImageDecoder Animated Tests

@Suite struct DownsamplingAnimatedDecoderTests {
    @Test("애니메이션 데이터도 다운샘플링 후 animated UIImage로 반환")
    func decodesAnimatedThumbnailFromAnimatedData() throws {
        // Given
        let data = makeAnimatedGIFData(width: 180, height: 120, frameCount: 2, frameDuration: 0.12)
        let target = CGSize(width: 50, height: 50)
        let sut = DownsamplingImageDecoder(
            targetSize: target,
            scale: 1.0,
            contentMode: .scaleAspectFit
        )

        // When
        let image = try sut.decode(data)

        // Then
        #expect(image.images?.count == 2)
        #expect(image.size.width <= target.width + 1)
        #expect(image.size.height <= target.height + 1)
    }
}

// MARK: - Helpers

private func makePNGData(width: Int, height: Int, color: UIColor = .red) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
    let image = renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return image.pngData() ?? Data()
}

private func makeAnimatedGIFData(
    width: Int,
    height: Int,
    frameCount: Int,
    frameDuration: TimeInterval
) -> Data {
    guard frameCount > 1 else { return Data() }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        "com.compuserve.gif" as CFString,
        frameCount,
        nil
    ) else { return Data() }

    let fileProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0,
        ],
    ]
    CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

    let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDuration,
        ],
    ]

    for index in 0 ..< frameCount {
        let color: UIColor = (index % 2 == 0) ? .red : .blue
        guard let cgImage = UIImage(data: makePNGData(width: width, height: height, color: color))?.cgImage else {
            return Data()
        }
        CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else { return Data() }
    return data as Data
}
