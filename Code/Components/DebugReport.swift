//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The page as it stands: its text, the setting it was laid out at, and a picture of it, in one zip.
enum DebugReport {
    /// Writes the three files into a folder and returns it zipped, ready to be shared.
    @MainActor
    static func make(pageText: String, settings: String) throws -> URL {
        let stamp = Self.stamp.string(from: .now)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reader-\(stamp)")

        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try pageText.write(to: folder.appendingPathComponent("page.txt"), atomically: true, encoding: .utf8)
        try settings.write(to: folder.appendingPathComponent("settings.txt"), atomically: true, encoding: .utf8)

        if let image = screenshot(), let png = image.pngData() {
            try png.write(to: folder.appendingPathComponent("screen.png"))
        }

        return try zipped(folder, named: "reader-\(stamp)")
    }

    /// The window as it is drawn, which is the page with its running heads and whatever bar is showing.
    @MainActor
    private static func screenshot() -> UIImage? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        guard let window else { return nil }

        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    /// `NSFileCoordinator` zips a folder when it is read for uploading, which saves carrying an archiver.
    private static func zipped(_ folder: URL, named name: String) throws -> URL {
        var coordinatorError: NSError?
        var result: Result<URL, Error>?

        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) {
            source in
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).zip")

            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: source, to: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }
        }

        if let coordinatorError { throw coordinatorError }

        guard let result else { throw CocoaError(.fileWriteUnknown) }

        return try result.get()
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

/// A file to share, which a sheet needs to be identifiable to present.
struct SharedFile: Identifiable {
    let url: URL

    var id: String { url.path }
}

/// The system's own share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [ url ], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
