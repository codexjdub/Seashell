import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConversion {
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

    /// The first image, turned as its orientation says, at full size.
    private static func upright(_ source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        guard orientation != 1,
              let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int
        else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
