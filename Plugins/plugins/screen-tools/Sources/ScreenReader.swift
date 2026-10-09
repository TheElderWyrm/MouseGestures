import Cocoa
import Vision

/// Text and QR-code reading with Apple's Vision framework.
enum ScreenReader {
    /// Recognised text, top to bottom, one line per observation. Empty when nothing was found.
    static func text(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// Payloads of every QR / barcode found.
    static func codes(in image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
