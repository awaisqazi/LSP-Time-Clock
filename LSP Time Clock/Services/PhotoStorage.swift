import Foundation
import UIKit

enum PhotoStorage {
    static var directory: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let photos = docs.appendingPathComponent("EmployeePhotos", isDirectory: true)
        if !fm.fileExists(atPath: photos.path) {
            try? fm.createDirectory(at: photos, withIntermediateDirectories: true)
        }
        return photos
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func save(_ image: UIImage) throws -> String {
        let normalized = image.normalizedForStorage()
        let fileName = "\(UUID().uuidString).jpg"
        let destination = url(for: fileName)
        guard let data = normalized.jpegData(compressionQuality: 0.82) else {
            throw NSError(
                domain: "PhotoStorage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode JPEG."]
            )
        }
        try data.write(to: destination, options: .atomic)
        return fileName
    }

    static func load(fileName: String) -> UIImage? {
        guard !fileName.isEmpty,
              let data = try? Data(contentsOf: url(for: fileName)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

private extension UIImage {
    func normalizedForStorage(maxDimension: CGFloat = 1024) -> UIImage {
        let size = self.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
