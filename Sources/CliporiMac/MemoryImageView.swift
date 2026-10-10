import SwiftUI
import CliporiCore

struct MemoryImageView: View {
    let record: Memory
    let store: MemoryStore
    var maxPixelSize = 512
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if failed {
                Label(L("图片无法加载"), systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else { ProgressView().controlSize(.small) }
        }
        .accessibilityLabel(L("图片预览"))
        .task(id: record.attachment) {
            image = nil; failed = false
            do {
                guard let attachment = record.attachment,
                      let data = try await store.imageData(attachment: attachment, thumbnail: maxPixelSize <= 512) else { throw ClipboardImageError.missing }
                let decoded = try await ClipboardImageProcessor.shared.display(data, attachment: attachment, maxPixelSize: maxPixelSize)
                try Task.checkCancellation()
                image = decoded
            } catch is CancellationError {} catch { if !Task.isCancelled { failed = true } }
        }
    }
}

struct MemoryPreview: View {
    let record: Memory
    let store: MemoryStore
    var body: some View {
        if record.kind == .image {
            VStack(spacing: 12) {
                MemoryImageView(record: record, store: store, maxPixelSize: 2560)
                if let size = record.imageSize {
                    Text("\(size.width) × \(size.height)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                if !record.body.isEmpty { Text(record.body).font(.system(size: 13)).lineLimit(3).textSelection(.enabled) }
            }.padding(20).frame(minWidth: 320, minHeight: 240)
        } else {
            ScrollView { Text(record.body).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
        }
    }
}
