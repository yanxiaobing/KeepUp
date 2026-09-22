import Foundation
import Testing
@testable import KeepUp

@Test func legacyPayloadRoundTripsMultipleBlocksAndUnicode() throws {
    let codec = JSONPayloadCodec()
    let original = ["text": String(repeating: "坚持运动🏃", count: 200)]
    let data = try JSONEncoder().encode(original)
    let encrypted = try codec.encrypt(data)
    #expect(try codec.decode([String: String].self, from: encrypted) == original)
    #expect(try codec.decode([String: String].self, from: data) == original)
}

@Test func legacyPayloadRejectsMalformedEnvelopes() throws {
    let codec = JSONPayloadCodec()
    for text in [#"{"_xb_encrypted":null}"#, #"{"_xb_encrypted":42}"#,
                 #"{"_xb_encrypted":""}"#, #"{"_xb_encrypted":"!!!"}"#,
                 #"{"_xb_encrypted":"YQ=="}"#] {
        #expect(throws: (any Error).self) { try codec.plaintext(Data(text.utf8)) }
    }
    let encrypted = try codec.encrypt(Data(#"{"value":1}"#.utf8))
    let brokenKey = JSONPayloadCodec(privateKeyPEM: "invalid")
    #expect(throws: (any Error).self) { try brokenKey.plaintext(encrypted) }
}

@Test func httpEncryptionFailureNeverInvokesTransport() async throws {
    let client = HTTPClient(codec: JSONPayloadCodec(publicKeyPEM: "invalid"), fetch: { _ in
        Issue.record("Encryption failure must not send a request")
        throw URLError(.unknown)
    })
    var request = URLRequest(url: URL(string: "https://example.invalid/config")!)
    request.httpBody = Data(#"{"value":1}"#.utf8)
    await #expect(throws: (any Error).self) { try await client.data(for: request, encryptBody: true) }
}

@Test @MainActor func encryptedIAAPLoadsBundlesRemoteAndPreservesCacheAfterCorruption() async throws {
    let codec = JSONPayloadCodec()
    let plain = try JSONEncoder().encode(IAAPConfiguration(system: [:], ads: [:],
        skus: [.init(pid: "com.bestlife.keepup.premium.lifetime", type: .lifetime, titleType: "timer")],
        iaaps: [.init(type: "vip", closeAlpha: 0.5, priceAlpha: 0.5, showGiveUp: true,
            iap: .init(pids: ["com.bestlife.keepup.premium.lifetime"], timeInterval: 5, hidePageControl: false))]))
    let encrypted = try codec.encrypt(plain)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = directory.appendingPathComponent("cache.json")
    let url = URL(string: "https://example.invalid/keepup.json")!
    let store = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: encrypted, fetch: { request in
        (encrypted, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    #expect(store.configuration.skus.count == 1)
    await store.refresh()
    #expect(store.source == .remote)
    let saved = try Data(contentsOf: cache)
    let restarted = IAAPConfigurationStore(remoteURL: url, cacheURL: cache, bundledData: encrypted, fetch: { request in
        (Data(#"{"_xb_encrypted":"broken"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    await restarted.refresh()
    #expect(restarted.source == .cache)
    #expect(restarted.lastError != nil)
    #expect(try Data(contentsOf: cache) == saved)
}

@Test func httpClientEncryptsRequestAndDecodesResponse() async throws {
    let payload = Data(#"{"message":"你好"}"#.utf8)
    let client = HTTPClient(fetch: { request in
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONPayloadCodec().plaintext(#require(request.httpBody)) == payload)
        return (try JSONPayloadCodec().encrypt(payload), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    var request = URLRequest(url: URL(string: "https://example.invalid/config")!)
    request.httpMethod = "POST"
    request.httpBody = payload
    #expect(try await client.data(for: request, encryptBody: true) == payload)
}

@Test func httpClientRejectsBadStatusInsecureURLAndOversizedResponse() async throws {
    let url = URL(string: "https://example.invalid/config")!
    for status in [400, 500] {
        let client = HTTPClient(fetch: { _ in
            (Data("{}".utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: HTTPClient.ClientError.self) { try await client.data(for: URLRequest(url: url)) }
    }
    let client = HTTPClient(maximumResponseBytes: 1, fetch: { _ in
        (Data("{}".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    await #expect(throws: HTTPClient.ClientError.self) { try await client.data(for: URLRequest(url: url)) }
    await #expect(throws: HTTPClient.ClientError.self) {
        try await client.data(for: URLRequest(url: URL(string: "http://example.invalid")!))
    }
}

// Independently generated with OpenSSL pkeyutl, RSA PKCS#1 v1.5 and the legacy public key.
@Test func legacyPayloadDecryptsIndependentOpenSSLFixture() throws {
    let fixture = Data(#"{"_xb_encrypted":"ZWdK5U37ngbB2ThAVkwzKJQsmc9YMUtvH7yrdHMyfILkRmyiWZ5qymST1qrlSg6dO+hk6v5HylzM2uGEAxUzmg=="}"#.utf8)
    #expect(try JSONPayloadCodec().decode([String: String].self, from: fixture) == ["text": "旧协议兼容🏃"])
}

@Test func bundledJSONUsesSharedEncryptedDecoder() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let info = ["CFBundleIdentifier": "test.keepup.network", "CFBundlePackageType": "BNDL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: directory.appendingPathComponent("Info.plist"))
    let data = try JSONPayloadCodec().encrypt(Data(#"{"text":"bundle"}"#.utf8))
    try data.write(to: directory.appendingPathComponent("fixture.json"))
    let bundle = try #require(Bundle(url: directory))
    #expect(try BundledJSON.decode([String: String].self, named: "fixture", bundle: bundle) == ["text": "bundle"])
}
