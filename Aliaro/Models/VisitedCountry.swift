import Foundation
import SwiftData
import CryptoKit

/// A country a family member has visited (World map). One row per member
/// and country; its `id` is derived from both (`VisitedCountry.id(for:code:)`),
/// so marking, unmarking and marking again — from any device — always
/// targets the same row.
@Model
final class VisitedCountry {
    var id: UUID
    /// Reference to `FamilyMember` (not a SwiftData relationship).
    var memberID: UUID
    /// ISO 3166-1 alpha-2 code ("ES"; "XK" for Kosovo).
    var countryCode: String
    var createdAt: Date

    init(memberID: UUID, countryCode: String, createdAt: Date = .now) {
        self.id = VisitedCountry.id(for: memberID, code: countryCode)
        self.memberID = memberID
        self.countryCode = countryCode
        self.createdAt = createdAt
    }

    init(id: UUID, memberID: UUID, countryCode: String, createdAt: Date) {
        self.id = id
        self.memberID = memberID
        self.countryCode = countryCode
        self.createdAt = createdAt
    }

    /// Name-based UUID (version 3, MD5) of "<member id>:<code>" — the same
    /// as Java's `UUID.nameUUIDFromBytes` on Android.
    static func id(for memberID: UUID, code: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data("\(memberID.uuidString.lowercased()):\(code)".utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Country helpers shared by the World map screens.
enum CountryInfo {
    /// Countries in the world, for the "% of the world" stat.
    static let worldCount = 195

    /// Localized name ("España"), or the code if the system doesn't know it.
    static func name(_ code: String) -> String {
        if code == "XK" { return Locale.current.localizedString(forRegionCode: code) ?? "Kosovo" }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    /// Flag emoji from the code's regional indicator symbols.
    static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }
}
