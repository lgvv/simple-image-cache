import ImageIO
import UIKit

/// ImageIO 기반 다운샘플링 디코더
public struct DownsamplingImageDecoder: ImageDecoder {
    /// 목표 출력 크기
    public let targetSize: CGSize
    /// 목표 출력 scale
    public let scale: CGFloat
    /// 출력 정렬 방식
    public let contentMode: ImageContentMode

    /// 다운샘플링 디코더를 생성
    ///
    /// - Parameters:
    ///   - targetSize: 목표 출력 크기
    ///   - scale: 목표 출력 scale
    ///   - contentMode: 출력 정렬 방식
    public init(
        targetSize: CGSize,
        scale: CGFloat = 1.0,
        contentMode: ImageContentMode = .scaleAspectFit
    ) {
        self.targetSize = targetSize
        self.scale = scale
        self.contentMode = contentMode
    }

    /// 이미지 데이터를 다운샘플링 후 디코딩
    ///
    /// - Parameter data: 원본 이미지 데이터
    /// - Returns: 다운샘플링된 이미지
    /// - Throws: 데이터가 비었거나 디코딩에 실패한 경우
    public func decode(_ data: Data) throws -> UIImage {
        guard !data.isEmpty else { throw ImageCacheError.emptyData }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImageCacheError.invalidImageData
        }

        let pixelWidth = targetSize.width * scale
        let pixelHeight = targetSize.height * scale

        let maxPixelSize: CGFloat
        if contentMode == .scaleAspectFill,
           let origW = originalPixelDimension(source, key: kCGImagePropertyPixelWidth),
           let origH = originalPixelDimension(source, key: kCGImagePropertyPixelHeight),
           origW > 0, origH > 0 {
            let fillScale = max(pixelWidth / origW, pixelHeight / origH)
            maxPixelSize = max(origW, origH) * fillScale
        } else {
            maxPixelSize = max(pixelWidth, pixelHeight)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        if let animated = AnimatedImageDecoder.decode(
            source: source,
            makeFrame: { index in
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    index,
                    thumbnailOptions as CFDictionary
                ) else { return nil }
                let downsampled = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
                return postProcess(downsampled)
            }
        ) {
            return animated
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else {
            throw ImageCacheError.invalidImageData
        }

        return postProcess(UIImage(cgImage: cgImage, scale: scale, orientation: .up))
    }

    private func postProcess(_ image: UIImage) -> UIImage {
        switch contentMode {
        case .scaleAspectFit:
            return image
        case .scaleAspectFill, .scaleToFill:
            return image.resized(to: targetSize, scale: scale, contentMode: contentMode)
        }
    }
    
    private func originalPixelDimension(_ source: CGImageSource, key: CFString) -> CGFloat? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let value = props[key] else { return nil }
        if let int = value as? Int { return CGFloat(int) }
        if let double = value as? Double { return CGFloat(double) }
        return nil
    }
}
