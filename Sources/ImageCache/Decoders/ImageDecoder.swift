import ImageIO
import UIKit

/// 이미지 데이터 디코더
public protocol ImageDecoder: Sendable {
    /// 이미지 데이터를 디코딩
    ///
    /// - Parameter data: 원본 이미지 데이터
    /// - Returns: 디코딩된 이미지
    /// - Throws: 데이터가 비었거나 디코딩에 실패한 경우
    func decode(_ data: Data) throws -> UIImage
}

/// 기본 `UIImage` 디코더
///
/// 정적 이미지는 `UIImage(data:)`
/// 애니메이션 이미지는 프레임 분해 후 `animatedImage`
public struct UIImageDecoder: ImageDecoder {
    /// 기본 이미지 디코더를 생성
    public init() {}

    /// 이미지 데이터를 디코딩
    ///
    /// - Parameter data: 원본 이미지 데이터
    /// - Returns: 디코딩된 이미지
    /// - Throws: 데이터가 비었거나 디코딩에 실패한 경우
    public func decode(_ data: Data) throws -> UIImage {
        guard !data.isEmpty else { throw ImageCacheError.emptyData }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
           let animated = AnimatedImageDecoder.decode(
               source: source,
               makeFrame: { index in
                   guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
                   return UIImage(cgImage: cgImage)
               }
           ) {
            return animated
        }

        guard let image = UIImage(data: data) else { throw ImageCacheError.invalidImageData }
        return image
    }
}

/// 애니메이션 이미지 조립기
///
/// GIF / WebP / APNG 프레임 디코딩
enum AnimatedImageDecoder {
    private static let minimumFrameDuration: TimeInterval = 0.02
    private static let defaultFrameDuration: TimeInterval = 0.1
    private static let maximumFrameCount = 120

    static func decode(
        source: CGImageSource,
        makeFrame: (Int) -> UIImage?
    ) -> UIImage? {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1, frameCount <= maximumFrameCount else { return nil }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var totalDuration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let frame = autoreleasepool(invoking: { makeFrame(index) }) else {
                return nil
            }
            frames.append(frame)
            totalDuration += frameDuration(source: source, index: index)
        }

        guard !frames.isEmpty else { return nil }
        if !totalDuration.isFinite || totalDuration <= 0 {
            totalDuration = defaultFrameDuration * Double(frames.count)
        }
        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return defaultFrameDuration
        }

        if let webP = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            return normalizedDuration(
                unclamped: webP[kCGImagePropertyWebPUnclampedDelayTime],
                clamped: webP[kCGImagePropertyWebPDelayTime]
            )
        }
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            return normalizedDuration(
                unclamped: gif[kCGImagePropertyGIFUnclampedDelayTime],
                clamped: gif[kCGImagePropertyGIFDelayTime]
            )
        }
        if let apng = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            return normalizedDuration(
                unclamped: apng[kCGImagePropertyAPNGUnclampedDelayTime],
                clamped: apng[kCGImagePropertyAPNGDelayTime]
            )
        }
        return defaultFrameDuration
    }

    private static func normalizedDuration(unclamped: Any?, clamped: Any?) -> TimeInterval {
        let candidate = numericValue(unclamped) ?? numericValue(clamped) ?? defaultFrameDuration
        guard candidate.isFinite, candidate > 0 else { return defaultFrameDuration }
        return max(candidate, minimumFrameDuration)
    }

    private static func numericValue(_ value: Any?) -> TimeInterval? {
        (value as? NSNumber)?.doubleValue
    }
}
