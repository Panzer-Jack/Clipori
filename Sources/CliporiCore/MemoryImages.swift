import Foundation

extension MemoryStore {
    /// The pixels and their record commit together. Normal history queries never load image blobs.
    public func saveImage(_ record: Memory, png: Data, thumbnail: Data, size: Memory.ImageSize) throws -> Memory {
        var image = record
        let attachmentID = UUID().uuidString
        image.kind = .image; image.attachment = attachmentID; image.imageSize = size
        try db.transaction {
            try db.execute("INSERT INTO image_attachments VALUES (?, ?, ?)", [.text(attachmentID), .blob(png), .blob(thumbnail)])
            try write(image)
        }
        return image
    }

    public func imageData(attachment: String, thumbnail: Bool = false) throws -> Data? {
        try db.data("SELECT \(thumbnail ? "thumbnail" : "png") FROM image_attachments WHERE id=?", [.text(attachment)])
    }

    /// Keep the bounded undo stack's attachments until they are restored or evicted.
    /// At startup the stack is empty, so previously deleted images can also be reclaimed.
    public func pruneImages(keeping undoAttachments: Set<String> = []) throws {
        try db.transaction {
            let unused = try db.rows("SELECT id FROM image_attachments WHERE id NOT IN (SELECT json_extract(payload, '$.attachment') FROM memories WHERE json_extract(payload, '$.attachment') IS NOT NULL)")
            for row in unused where !undoAttachments.contains(row[0]) {
                try db.execute("DELETE FROM image_attachments WHERE id=?", [.text(row[0])])
            }
        }
    }
}
