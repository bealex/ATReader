//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// How much room a file or a folder takes on the disk.
///
/// The blocks a file is given rather than the bytes written into it, which is what the device counts
/// against its free space and what comes back when the file goes.
public enum DiskSpace {
    /// What this file takes, or everything under it where it is a folder.
    public static func taken(by url: URL) -> Int64 {
        let isFolder = (try? url.resourceValues(forKeys: [ .isDirectoryKey ]))?.isDirectory == true

        guard isFolder else { return taken(byFile: url) }
        guard
            let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(Self.keys))
        else { return 0 }

        return walk.reduce(into: Int64(0)) { total, entry in
            guard let file = entry as? URL else { return }

            total += taken(byFile: file)
        }
    }

    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    /// Never less than what the file holds: one kept in the cloud and not downloaded here is allocated
    /// nothing on this device and is still that big.
    private static func taken(byFile url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Self.keys) else { return 0 }

        let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0

        return Int64(max(allocated, values.fileSize ?? 0))
    }
}
