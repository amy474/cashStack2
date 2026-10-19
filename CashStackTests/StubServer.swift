import Foundation

/// Answers URLSession requests in-process, so the API client and the crash
/// report outbox can be tested without a server or a network. Each stub has
/// a made-up host of its own, so tests running side by side never answer
/// each other's requests.
final class StubServer: @unchecked Sendable {

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        var json: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    /// A status and a JSON body, or a thrown URLError for "no network".
    typealias Responder = @Sendable (Request) throws -> (status: Int, json: Any?)

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    var base: URL { URL(string: "https://\(host)")! }

    private let lock = NSLock()
    private var received: [Request] = []
    private let respond: Responder

    init(_ respond: @escaping Responder) {
        self.respond = respond
        StubProtocol.register(self)
    }

    deinit { StubProtocol.unregister(host) }

    /// Every request the stub has answered, in order.
    var requests: [Request] { lock.withLock { received } }

    /// A session configuration that sends this stub's host to it.
    func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return config
    }

    fileprivate func handle(_ request: Request) throws -> (Int, Data) {
        lock.withLock { received.append(request) }
        let (status, json) = try respond(request)
        let data = try json.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return (status, data)
    }
}

/// Mutable state a responder can change between requests.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class StubProtocol: URLProtocol {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer) { lock.withLock { servers[server.host] = server } }
    static func unregister(_ host: String) { _ = lock.withLock { servers.removeValue(forKey: host) } }
    private static func server(for request: URLRequest) -> StubServer? {
        guard let host = request.url?.host else { return nil }
        return lock.withLock { servers[host] }
    }

    override class func canInit(with request: URLRequest) -> Bool { server(for: request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = Self.server(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let stub = StubServer.Request(method: request.httpMethod ?? "GET",
                                      path: url.path,
                                      headers: request.allHTTPHeaderFields ?? [:],
                                      body: request.httpBody ?? request.httpBodyStream.map(Self.readAll))
        do {
            let (status, data) = try server.handle(stub)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession hands a protocol the body as a stream, not as `httpBody`.
    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
