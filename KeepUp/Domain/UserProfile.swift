import Foundation

enum ProfileChange: Sendable {
    case nickname(String), motto(String), avatar(Data), gender(Bool), year(Int), height(Double), weight(Double)
    func applying(to profile: UserProfile) -> UserProfile {
        var result = profile
        switch self {
        case .nickname(let value): result.nickname = value
        case .motto(let value): result.motto = value
        case .avatar(let value): result.avatar = value
        case .gender(let value): result.isMale = value
        case .year(let value): result.year = value
        case .height(let value): result.height = value
        case .weight(let value): result.weight = value
        }
        return result
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    var nickname = ""
    var motto: String?
    var avatar: Data?
    var isMale = false
    var year = 1995
    var height = 165.0
    var weight = 60.0
    var createdAt = Date.now

    func validated() throws -> Self {
        var value = self
        value.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        value.motto = motto?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.nickname.utf16.count <= 7, (1940...2019).contains(year),
              (value.motto?.utf16.count ?? 0) <= 40,
              height.isFinite, (100...220).contains(height), weight.isFinite, (5...200).contains(weight),
              (avatar?.count ?? 0) <= 5_000_000 else { throw StoreError.invalidProfile }
        return value
    }
}
