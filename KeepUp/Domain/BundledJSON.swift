import Foundation

/// Required, version-controlled app configuration. Never silently substitute an empty catalog.
enum BundledJSON {
    enum ConfigurationError: Error { case missingResource(String), invalid(String) }

    static func decode<T: Decodable>(_ type: T.Type, named name: String, bundle: Bundle = .main) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ConfigurationError.missingResource(name)
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func required<T: Decodable>(_ type: T.Type, named name: String, validate: (T) throws -> Void) -> T {
        do {
            let value = try decode(type, named: name)
            try validate(value)
            return value
        } catch {
            preconditionFailure("Invalid bundled configuration \(name).json: \(error)")
        }
    }
}
