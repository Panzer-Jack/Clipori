import AppKit
import ImageIO
import UniformTypeIdentifiers
import CliporiCore

enum ClipboardImageError: LocalizedError {
    case invalid, tooLarge, missing, writeFailed
    var errorDescription: String? {
        switch self {
        case .invalid: return L("无法读取这张图片。")
        case .tooLarge: return L("图片过大，暂不收录超过 128 MB 或 8000 万像素的图片。")
        case .missing: return L("图片数据已不存在，无法预览或复制。")
        case .writeFailed: return L("无法写入剪贴板，请重试。")
        }
    }
}

/// ImageIO decoding and encoding stay off the main actor, including TIFF supplied by screenshots.
actor ClipboardImageProcessor {
    static let shared = ClipboardImageProcessor()
    struct Prepared: Sendable {
        let png: Data
        let thumbnail: Data
        let size: Memory.ImageSize
    }
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 12 * 1024 * 1024 }

    func prepare(_ data: Data) throws -> Prepared {
        let source = try source(data)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ClipboardImageError.invalid }
        guard Double(width) * Double(height) <= 80_000_000 else { throw ClipboardImageError.tooLarge }
        let image = try decode(source, maxPixelSize: max(width, height))
        let thumbnail = try decode(source, maxPixelSize: 512)
        let png = try encode(image, type: .png)
        guard png.count <= 128 * 1024 * 1024 else { throw ClipboardImageError.tooLarge }
        return Prepared(png: png, thumbnail: try encode(thumbnail, type: .png),
                        size: .init(width: image.width, height: image.height))
    }
    func display(_ data: Data, attachment: String, maxPixelSize: Int) throws -> CGImage {
        let key = "\(attachment)-\(maxPixelSize)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = try decode(source(data), maxPixelSize: maxPixelSize)
        // Full previews are owned only by the open window, not the thumbnail cache.
        if maxPixelSize <= 512 { cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height) }
        return image
    }
    func tiff(from png: Data) throws -> Data {
        let source = try source(png)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ClipboardImageError.invalid }
        return try encode(image, type: .tiff)
    }
    private func source(_ data: Data) throws -> CGImageSource {
        guard data.count <= 128 * 1024 * 1024 else { throw ClipboardImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ClipboardImageError.invalid }
        return source
    }
    private func decode(_ source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                                      kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ClipboardImageError.invalid }
        return image
    }
    private func encode(_ image: CGImage, type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw ClipboardImageError.invalid }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipboardImageError.invalid }
        return data as Data
    }
}
