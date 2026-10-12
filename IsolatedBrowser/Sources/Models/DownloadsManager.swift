import Foundation

struct DownloadedFile: Identifiable, Equatable {
    let id: String
    let filename: String
    let fileURL: URL
    let fileSize: Int64
    let date: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

final class DownloadsManager {
    static let shared = DownloadsManager()

    let downloadsDirectory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.downloadsDirectory = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
    }

    func destinationURL(for suggestedFilename: String) -> URL {
        let cleanName = (suggestedFilename.isEmpty ? "document" : suggestedFilename)
            .replacingOccurrences(of: "/", with: "_")
        let target = downloadsDirectory.appendingPathComponent(cleanName)

        if !FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        let nameWithoutExt = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueName = ext.isEmpty ? "\(nameWithoutExt)_\(timestamp)" : "\(nameWithoutExt)_\(timestamp).\(ext)"
        return downloadsDirectory.appendingPathComponent(uniqueName)
    }

    func listDownloads() -> [DownloadedFile] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory,
                                                                      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                                      options: [.skipsHiddenFiles]) else {
            return []
        }

        return items.compactMap { url -> DownloadedFile? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }
            return DownloadedFile(
                id: url.lastPathComponent,
                filename: url.lastPathComponent,
                fileURL: url,
                fileSize: Int64(values.fileSize ?? 0),
                date: values.contentModificationDate ?? Date()
            )
        }.sorted { $0.date > $1.date }
    }

    func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
