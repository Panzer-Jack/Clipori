import CloudKit
import Combine
import Foundation

@MainActor
public final class CloudSyncController: ObservableObject {
    @Published public private(set) var status = L("iCloud 同步已关闭")
    @Published public private(set) var isSyncing = false
    public let available: Bool
    private let store: MemoryStore
    private let directory: URL
    private var worker: CloudSyncEngine?
    private var loop: Task<Void, Never>?
    private var enabled = false
    public var onReceive: (() async -> Void)?

    public init(store: MemoryStore, directory: URL) {
        self.store = store; self.directory = directory
        available = !(Bundle.main.object(forInfoDictionaryKey: "CliporiCloudContainer") as? String ?? "").isEmpty
    }
    public func setEnabled(_ value: Bool) async {
        enabled = value; loop?.cancel(); loop = nil
        if !value { await worker?.stop(); worker = nil; status = L("iCloud 同步已关闭"); return }
        guard available else { status = L("此构建尚未配置 iCloud 签名与容器"); return }
        if worker == nil, let identifier = Bundle.main.object(forInfoDictionaryKey: "CliporiCloudContainer") as? String {
            worker = CloudSyncEngine(store: store, directory: directory, containerIdentifier: identifier)
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }
    public func syncNow() async {
        guard enabled, let worker, !isSyncing else { return }
        isSyncing = true; status = L("正在同步…")
        defer { isSyncing = false }
        do {
            let changed = try await worker.synchronize()
            guard enabled else { return }
            status = L("已同步 · ") + Date().formatted(date: .omitted, time: .shortened)
            if changed { await onReceive?() }
        } catch is CancellationError {} catch { status = error.localizedDescription }
    }
}

private struct CloudSyncError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// CKSyncEngine owns change tokens. SQLite owns a durable outbox, so a crash cannot lose an edit.
private actor CloudSyncEngine: CKSyncEngineDelegate {
    private let store: MemoryStore
    private let directory: URL
    private let container: CKContainer
    private let zone = CKRecordZone.ID(zoneName: "CliporiMemories")
    private var engine: CKSyncEngine?
    private var sessionError: Error?
    private var changed = false
    private var stopped = false
    private var uploads: [String: URL] = [:]

    init(store: MemoryStore, directory: URL, containerIdentifier: String) {
        self.store = store; self.directory = directory.appendingPathComponent("SyncUploads", isDirectory: true)
        container = CKContainer(identifier: containerIdentifier)
    }
    func stop() async { stopped = true; await engine?.cancelOperations() }

    func synchronize() async throws -> Bool {
        do { return try await performSync() }
        catch {
            await engine?.cancelOperations()
            engine = nil
            throw error
        }
    }
    private func performSync() async throws -> Bool {
        guard !stopped else { throw CancellationError() }
        sessionError = nil; changed = false
        guard try await container.accountStatus() == .available else { throw CloudSyncError(message: L("请先在系统设置中登录 iCloud")) }
        let user = try await container.userRecordID().recordName
        if let previous = try await store.syncMetadata("account"), previous != Data(user.utf8) {
            throw CloudSyncError(message: L("Apple 账号已变更，已暂停同步以保留本机数据；请切回原账号。"))
        }
        try await store.setSyncMetadata("account", data: Data(user.utf8))
        if engine == nil {
            let state = try await store.syncMetadata("state").map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
            var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: self)
            // Explicit foreground cycles let us verify the account before every send.
            config.automaticallySync = false
            engine = CKSyncEngine(config)
        }
        guard let engine else { throw CancellationError() }
        try await engine.fetchChanges()
        try checkSession()
        var pending = try await store.syncPending()
        if !pending.isEmpty { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))]) }
        while !pending.isEmpty {
            try checkSession()
            let keys = pending.map(\.key)
            engine.state.add(pendingRecordZoneChanges: keys.map { .saveRecord(CKRecord.ID(recordName: $0, zoneID: zone)) })
            try await engine.sendChanges()
            try checkSession()
            pending = try await store.syncPending()
            // Retry transient errors on a later cycle instead of spinning the network.
            if pending.map(\.key) == keys { break }
        }
        return changed
    }
    private func checkSession() throws {
        try Task.checkCancellation()
        if stopped { throw CancellationError() }
        if let sessionError { throw sessionError }
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        do {
            switch event {
            case .stateUpdate(let update):
                // Never advance the persisted cursor past an unapplied batch.
                if sessionError == nil { try await store.setSyncMetadata("state", data: JSONEncoder().encode(update.stateSerialization)) }
            case .accountChange(let account):
                switch account.changeType {
                case .signIn(let current):
                    if let saved = try await store.syncMetadata("account"), saved != Data(current.recordName.utf8) { stopped = true }
                case .signOut, .switchAccounts: stopped = true
                @unknown default: stopped = true
                }
                if stopped { throw CloudSyncError(message: L("Apple 账号状态已变化，同步已暂停，本机记录仍然保留。")) }
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zone }) {
                    stopped = true
                    throw CloudSyncError(message: L("云端记录区域已被移除，同步已暂停，本机记录仍然保留。"))
                }
            case .fetchedRecordZoneChanges(let changes):
                try checkSession()
                for modification in changes.modifications {
                    changed = try await receive(modification.record) || changed
                }
                for deletion in changes.deletions {
                    let key = deletion.recordID.recordName
                    if let dash = key.firstIndex(of: "-"), let kind = SyncEnvelope.Kind(rawValue: String(key[..<dash])),
                       let id = UUID(uuidString: String(key[key.index(after: dash)...])) {
                        changed = try await store.mergeRemote(.init(deleting: id, kind: kind, at: Date())) || changed
                        try await store.syncForgetFields(key: key)
                    }
                }
            case .sentRecordZoneChanges(let sent):
                for record in sent.savedRecords {
                    let envelope = try envelope(from: record)
                    try await store.syncAcknowledge(envelope, systemFields: fields(of: record))
                    if let file = uploads.removeValue(forKey: record.recordID.recordName) { try? FileManager.default.removeItem(at: file) }
                }
                for failure in sent.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                        changed = try await receive(server) || changed
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                    } else if failure.error.code == .unknownItem {
                        let key = failure.record.recordID.recordName
                        if let local = try await store.syncEnvelope(key: key) {
                            changed = try await store.mergeRemote(.init(deleting: local.id, kind: local.kind, at: Date())) || changed
                            try await store.syncForgetFields(key: key)
                            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                        }
                    } else { sessionError = failure.error }
                }
            case .sentDatabaseChanges(let sent):
                if let error = sent.failedZoneSaves.first?.error { sessionError = error }
            case .didFetchRecordZoneChanges(let fetched):
                if let error = fetched.error, error.code != .zoneNotFound { sessionError = error }
            default: break
            }
        } catch { sessionError = error }
    }
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        do {
            try checkSession()
            var records: [CKRecord.ID: CKRecord] = [:]
            let changes = Array(syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }.prefix(100))
            for change in changes {
                guard case .saveRecord(let id) = change else { continue }
                guard let envelope = try await store.syncEnvelope(key: id.recordName) else {
                    syncEngine.state.remove(pendingRecordZoneChanges: [change]); continue
                }
                let record: CKRecord
                if let data = try await store.syncFields(key: id.recordName), !data.isEmpty {
                    let coder = try NSKeyedUnarchiver(forReadingFrom: data); coder.requiresSecureCoding = true
                    defer { coder.finishDecoding() }
                    record = CKRecord(coder: coder) ?? CKRecord(recordType: "CliporiEntry", recordID: id)
                } else { record = CKRecord(recordType: "CliporiEntry", recordID: id) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(UUID().uuidString + ".json")
                try JSONEncoder().encode(envelope).write(to: url, options: .atomic)
                if let previous = uploads.updateValue(url, forKey: id.recordName) { try? FileManager.default.removeItem(at: previous) }
                record["content"] = CKAsset(fileURL: url)
                records[id] = record
            }
            let snapshot = records
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { snapshot[$0] }
        } catch { sessionError = error; return nil }
    }
    private func receive(_ record: CKRecord) async throws -> Bool {
        guard record.recordType == "CliporiEntry", record.recordID.zoneID == zone else { return false }
        let envelope = try envelope(from: record)
        guard envelope.key == record.recordID.recordName else { throw CloudSyncError(message: L("云端记录标识不一致")) }
        return try await store.mergeRemote(envelope, systemFields: fields(of: record))
    }
    private func envelope(from record: CKRecord) throws -> SyncEnvelope {
        guard let asset = record["content"] as? CKAsset, let url = asset.fileURL else { throw CloudSyncError(message: L("云端记录内容缺失")) }
        return try JSONDecoder().decode(SyncEnvelope.self, from: Data(contentsOf: url))
    }
    private func fields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding(); return coder.encodedData
    }
}
