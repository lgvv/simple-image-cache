import UIKit

/// `UIImage` 디코딩 후 리사이징하는 디코더
public struct ResizingImageDecoder: ImageDecoder {
    /// 목표 출력 크기
    public let targetSize: CGSize
    /// 목표 출력 scale
    public let scale: CGFloat
    /// 출력 정렬 방식
    public let contentMode: ImageContentMode

    /// 리사이징 디코더를 생성
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

    /// 이미지 데이터를 디코딩 후 리사이즈
    ///
    /// - Parameter data: 원본 이미지 데이터
    /// - Returns: 리사이즈된 이미지
    /// - Throws: 데이터가 비었거나 디코딩에 실패한 경우
    public func decode(_ data: Data) throws -> UIImage {
        guard !data.isEmpty else { throw ImageCacheError.emptyData }
        guard let image = UIImage(data: data) else { throw ImageCacheError.invalidImageData }
        return image.resized(to: targetSize, scale: scale, contentMode: contentMode)
    }
}
