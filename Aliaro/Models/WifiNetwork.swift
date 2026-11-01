import Foundation
import SwiftData

/// A Wi-Fi network saved by the family (home, the village house…), shown
/// on everyone's Home with its password and a QR code guests can scan.
@Model
final class WifiNetwork {
    var id: UUID
    /// Display name ("Home"); empty = show the SSID.
    var label: String
    var ssid: String
    var password: String
    /// `WifiNetwork.Security.rawValue`.
    var security: String
    var position: Int
    var createdAt: Date
    var updatedAt: Date
    var createdByID: UUID?
    var createdByName: String?

    enum Security: String, CaseIterable, Identifiable {
        case wpa = "WPA", wep = "WEP", none = "nopass"

        var id: String { rawValue }
    }

    var securityType: Security { Security(rawValue: security) ?? .wpa }
    var displayName: String { label.isEmpty ? ssid : label }

    /// Standard Wi-Fi QR payload (camera apps on iOS and Android join from it).
    var qrPayload: String {
        func escape(_ value: String) -> String {
            var result = ""
            for ch in value {
                if "\\;,:\"".contains(ch) { result.append("\\") }
                result.append(ch)
            }
            return result
        }
        let pass = securityType == .none ? "" : "P:\(escape(password));"
        return "WIFI:T:\(securityType.rawValue);S:\(escape(ssid));\(pass);"
    }

    static let maxLabelLength = 40
    static let maxSSIDLength = 32
    static let maxPasswordLength = 63

    init(
        id: UUID = UUID(),
        label: String = "",
        ssid: String,
        password: String = "",
        security: Security = .wpa,
        position: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.label = label
        self.ssid = ssid
        self.password = password
        self.security = security.rawValue
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}
