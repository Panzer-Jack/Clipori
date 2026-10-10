import SwiftUI
import CliporiCore

@main
struct CliporiApp: App {
    private let result: Result<MobileModel, Error>
    init() { result = Result { try MobileModel() } }
    var body: some Scene {
        WindowGroup {
            switch result {
            case .success(let model): MobileHome(model: model)
            case .failure(let error): ContentUnavailableView(L("暂时无法打开记忆空间"), systemImage: "externaldrive.badge.exclamationmark", description: Text(error.localizedDescription))
            }
        }
    }
}
