import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case on = "AWDL On"
    case off = "AWDL Off"
    case automatic = "Automatic"

    var id: String { rawValue }

    func suppressesAWDL(hasRunningTrigger: Bool, usesWiFi: Bool) -> Bool {
        switch self {
        case .on: false
        case .off: true
        case .automatic: hasRunningTrigger && usesWiFi
        }
    }
}

struct TriggerApp: Codable, Identifiable {
    let id: String
    let name: String
}
