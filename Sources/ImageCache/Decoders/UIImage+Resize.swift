import UIKit

/// 공용 리사이즈 헬퍼
///
/// `DownsamplingImageDecoder` / `ResizingImageDecoder` 공용 사용
extension UIImage {
    /// 이미지 리사이즈
    ///
    /// - Parameters:
    ///   - targetSize: 출력 포인트 크기
    ///   - scale: 출력 scale
    ///   - contentMode: 리사이징 방식
    func resized(
        to targetSize: CGSize,
        scale: CGFloat,
        contentMode: ImageContentMode
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            drawScaled(in: CGRect(origin: .zero, size: targetSize),
                       contentMode: contentMode)
        }
    }

    // MARK: - Private

    private func drawScaled(in bounds: CGRect, contentMode: ImageContentMode) {
        switch contentMode {
        case .scaleAspectFit:
            draw(in: aspectFitRect(in: bounds))
        case .scaleAspectFill:
            draw(in: aspectFillRect(in: bounds))
        case .scaleToFill:
            draw(in: bounds)
        }
    }

    /// aspect fit 그리기 영역
    private func aspectFitRect(in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let srcAspect = size.width / size.height
        let dstAspect = bounds.width / bounds.height
        if srcAspect > dstAspect {
            // 너비 기준
            let drawHeight = bounds.width / srcAspect
            let y = (bounds.height - drawHeight) / 2
            return CGRect(x: 0, y: y, width: bounds.width, height: drawHeight)
        } else {
            // 높이 기준
            let drawWidth = bounds.height * srcAspect
            let x = (bounds.width - drawWidth) / 2
            return CGRect(x: x, y: 0, width: drawWidth, height: bounds.height)
        }
    }

    /// aspect fill 그리기 영역
    private func aspectFillRect(in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let srcAspect = size.width / size.height
        let dstAspect = bounds.width / bounds.height
        if srcAspect > dstAspect {
            // 높이 기준 / 가로 크롭
            let drawWidth = bounds.height * srcAspect
            let x = (bounds.width - drawWidth) / 2
            return CGRect(x: x, y: 0, width: drawWidth, height: bounds.height)
        } else {
            // 너비 기준 / 세로 크롭
            let drawHeight = bounds.width / srcAspect
            let y = (bounds.height - drawHeight) / 2
            return CGRect(x: 0, y: y, width: bounds.width, height: drawHeight)
        }
    }
}
