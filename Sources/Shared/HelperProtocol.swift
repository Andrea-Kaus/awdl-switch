import Foundation
import Security

enum HelperService {
    static let appID = "com.andreakaus.awdlswitch"
    static let name = "com.andreakaus.awdlswitch.helper"
    static let plistName = name + ".plist"
    static let installedPlist = "/Library/LaunchDaemons/" + plistName
    static let clientHashVariable = "AWDL_CLIENT_CDHASH"

    static func signingRequirement(for identifier: String) -> String? {
        guard let team = BuildSigning.teamID else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }

    static func signingRequirement(for identifier: String, hash: String) -> String? {
        guard hash.utf8.count == 40,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return "identifier \"\(identifier)\" and cdhash H\"\(hash)\""
    }

    static func bundledHelperRequirement() -> String? {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("AWDLSwitchHelper") else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let hash = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return signingRequirement(for: name, hash: hash.map { String(format: "%02x", $0) }.joined())
    }
}

@objc protocol AWDLHelperProtocol {
    func setSuppressed(_ suppressed: Bool, withReply reply: @escaping (String?) -> Void)
}
