import Foundation
import ImageIO
import CoreGraphics
import AfterglowCore

enum ArtworkReference: Sendable { case remote(URL), embedded(Data) }

enum AlbumArtwork {
    static func color(from reference: ArtworkReference) async throws -> GlowColor? {
        let data: Data
        switch reference {
        case .embedded(let bytes): data = bytes
        case .remote(let url):
            guard allowed(url) else { return nil }
            var request = URLRequest(url: url); request.timeoutInterval = 8
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            let session = URLSession(configuration: config, delegate: ArtworkRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            data = bytes
        }
        try Task.checkCancellation()
        guard data.count <= 8_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let width = 64, height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let extracted: GlowColor? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return AlbumPalette.extract(rgba: Array(buffer))
        }
        return extracted
    }

    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co") || host == "spotifycdn.com" || host.hasSuffix(".spotifycdn.com")
    }
}

private final class ArtworkRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(AlbumArtwork.allowed) == true ? request : nil)
    }
}
