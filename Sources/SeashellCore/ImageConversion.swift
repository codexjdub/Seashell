import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConversion {
    /// PNG data for any image format ImageIO can read. PNG input is returned as is.
    static func png(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw FileMoverError.unreadableImage }
        if UTType(type as String) == .png { return data }

        let output = NSMutableData()
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw FileMoverError.unreadableImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FileMoverError.unreadableImage }
        return output as Data
    }
}
