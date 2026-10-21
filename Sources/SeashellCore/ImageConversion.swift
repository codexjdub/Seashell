import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageConversion {
    /// The picture formats macOS can open (not SVG, say), as type identifiers.
    public static let readableTypes = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    /// PNG data for any image format ImageIO can read. PNG input is returned as
    /// is. A photo stored on its side (its EXIF orientation) comes out upright.
    static func png(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw FileMoverError.unreadableImage }
        if UTType(type as String) == .png { return data }

        let output = NSMutableData()
        guard let image = upright(source),
              let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw FileMoverError.unreadableImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FileMoverError.unreadableImage }
        return output as Data
    }

    /// An image (the first unless `index` says), turned as its orientation says, at full size.
    static func upright(_ source: CGImageSource, index: Int = 0) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        guard orientation != 1,
              let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int
        else { return CGImageSourceCreateImageAtIndex(source, index, nil) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }
}
