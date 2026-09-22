import Foundation
import Alamofire

struct HTTPClient: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    enum ClientError: Error { case invalidURL, invalidResponse, oversizedResponse }
    var codec = JSONPayloadCodec()
    var maximumResponseBytes = 1_048_576
    var fetch: Fetch = liveFetch

    static let liveFetch: Fetch = { request in
        let response = await AF.request(request).serializingData().response
        let data = try response.result.get()
        guard let http = response.response else { throw ClientError.invalidResponse }
        return (data, http)
    }

    /// Encrypt before invoking transport; failures never fall back to plaintext.
    func data(for request: URLRequest, encryptBody: Bool = false) async throws -> Data {
        guard let url = request.url, Self.isHTTPS(url) else { throw ClientError.invalidURL }
        var request = request
        if encryptBody {
            guard let body = request.httpBody else { throw JSONPayloadCodec.CodecError.invalidEnvelope }
            request.httpBody = try codec.encrypt(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        try Task.checkCancellation()
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = http.url, Self.isHTTPS(finalURL) else { throw ClientError.invalidResponse }
        guard data.count <= maximumResponseBytes else { throw ClientError.oversizedResponse }
        let plaintext = try codec.plaintext(data)
        guard plaintext.count <= maximumResponseBytes else { throw ClientError.oversizedResponse }
        return plaintext
    }

    static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host?.isEmpty ?? true) && url.user == nil && url.password == nil
    }
}
