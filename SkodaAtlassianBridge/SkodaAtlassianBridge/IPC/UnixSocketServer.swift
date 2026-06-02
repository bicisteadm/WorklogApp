import Foundation
import Darwin

/// Minimal HTTP/1.1 server bound to a Unix domain socket. Accepts only what
/// the bridge actually needs: `GET /health`, `GET /services`, `POST /fetch`.
/// No keep-alive, no chunked, no compression — every connection is
/// request → response → close.
///
/// File-system permissions on the socket file (`0600`) prevent other
/// macOS users from connecting. Per-request Bearer token (in Keychain)
/// prevents other processes of the same user from issuing calls without
/// reading the Keychain item first.
final class UnixSocketServer {
    private let socketPath: String
    private let token: String
    private let handler: (HTTPRequest) async -> HTTPResponse

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let acceptQueue = DispatchQueue(label: "bridge.accept")
    private let connectionQueue = DispatchQueue(label: "bridge.conn", attributes: .concurrent)

    init(
        socketPath: String,
        token: String,
        handler: @escaping (HTTPRequest) async -> HTTPResponse
    ) {
        self.socketPath = socketPath
        self.token = token
        self.handler = handler
    }

    deinit { stopSync() }

    func start() throws {
        try ensureParentDirectory()
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posix("socket") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        if pathBytes.count >= MemoryLayout.size(ofValue: addr.sun_path) {
            close(fd)
            throw IPCError.pathTooLong(socketPath)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes + [0])
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.bind(fd, sp, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw posix("bind")
        }

        chmod(socketPath, 0o600)
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw posix("listen")
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptOnce() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        acceptSource = source

        NSLog("SkodaAtlassianBridge: listening on unix:%@", socketPath)
    }

    func stop() { stopSync() }

    private func stopSync() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func ensureParentDirectory() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func acceptOnce() {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                accept(listenFD, sp, &clientLen)
            }
        }
        guard clientFD >= 0 else { return }
        connectionQueue.async { [weak self] in
            self?.handleConnection(clientFD: clientFD)
        }
    }

    private func handleConnection(clientFD: Int32) {
        defer { close(clientFD) }
        do {
            let req = try readHTTPRequest(fd: clientFD)
            let response: HTTPResponse
            if !req.isAuthorized(expectedToken: token) {
                response = .json(status: 401, body: ErrorResponseDTO(error: "Missing or invalid bearer token"))
            } else {
                response = runHandlerBlocking(req)
            }
            try writeResponse(fd: clientFD, response: response)
        } catch {
            // Best-effort error report; client may already be gone.
            let resp = HTTPResponse.json(status: 400, body: ErrorResponseDTO(error: "\(error)"))
            _ = try? writeResponse(fd: clientFD, response: resp)
        }
    }

    /// Bridge between the async handler and the blocking socket-handling thread.
    private func runHandlerBlocking(_ req: HTTPRequest) -> HTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var result: HTTPResponse = .json(status: 500, body: ErrorResponseDTO(error: "no result"))
        Task {
            result = await handler(req)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - HTTP request parsing

    private func readHTTPRequest(fd: Int32) throws -> HTTPRequest {
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        // Read until we have the full header section (terminated by \r\n\r\n).
        var headerEnd: Int? = nil
        while headerEnd == nil {
            let n = recv(fd, &chunk, chunkSize, 0)
            if n <= 0 { throw IPCError.clientClosed }
            buffer.append(chunk, count: n)
            headerEnd = findHeaderEnd(in: buffer)
            if buffer.count > 1_048_576 { throw IPCError.headerTooLarge }
        }
        guard let endIdx = headerEnd else { throw IPCError.headerTooLarge }

        let headerData = buffer.prefix(endIdx)
        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            throw IPCError.malformedRequest("non-UTF8 headers")
        }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw IPCError.malformedRequest("empty request") }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw IPCError.malformedRequest("bad request line: \(requestLine)") }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = endIdx + 4 // after \r\n\r\n
        var body = buffer.subdata(in: bodyStart..<buffer.count)
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        while body.count < contentLength {
            let n = recv(fd, &chunk, chunkSize, 0)
            if n <= 0 { throw IPCError.clientClosed }
            body.append(chunk, count: n)
        }
        if body.count > contentLength {
            body = body.prefix(contentLength)
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        var i = 0
        while i <= bytes.count - 4 {
            if bytes[i] == 0x0D && bytes[i + 1] == 0x0A && bytes[i + 2] == 0x0D && bytes[i + 3] == 0x0A {
                return i
            }
            i += 1
        }
        return nil
    }

    private func writeResponse(fd: Int32, response: HTTPResponse) throws {
        let payload = response.encodeHTTP()
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = send(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent, 0)
                if n <= 0 { throw IPCError.writeFailed }
                sent += n
            }
        }
    }

    private func posix(_ op: String) -> Error {
        IPCError.posix(op: op, errno: errno, message: String(cString: strerror(errno)))
    }
}

// MARK: - HTTP types

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]   // names lowercased
    let body: Data

    func isAuthorized(expectedToken: String) -> Bool {
        guard let auth = headers["authorization"] else { return false }
        let prefix = "Bearer "
        guard auth.hasPrefix(prefix) else { return false }
        let provided = String(auth.dropFirst(prefix.count))
        return constantTimeEquals(provided, expectedToken)
    }
}

struct HTTPResponse {
    let status: Int
    let reason: String
    let headers: [String: String]
    let body: Data

    static func json<T: Encodable>(status: Int, body: T) -> HTTPResponse {
        let data = (try? JSONEncoder.bridge.encode(body)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            reason: reasonPhrase(status),
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    func encodeHTTP() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var hdrs = headers
        hdrs["Content-Length"] = String(body.count)
        hdrs["Connection"] = "close"
        for (k, v) in hdrs {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

private func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 500: return "Internal Server Error"
    case 502: return "Bad Gateway"
    case 503: return "Service Unavailable"
    default:  return "Status"
    }
}

private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let aBytes = [UInt8](a.utf8)
    let bBytes = [UInt8](b.utf8)
    if aBytes.count != bBytes.count { return false }
    var diff: UInt8 = 0
    for i in 0..<aBytes.count {
        diff |= aBytes[i] ^ bBytes[i]
    }
    return diff == 0
}

enum IPCError: LocalizedError {
    case posix(op: String, errno: Int32, message: String)
    case pathTooLong(String)
    case clientClosed
    case headerTooLarge
    case malformedRequest(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .posix(let op, let err, let msg): return "\(op) failed (errno \(err)): \(msg)"
        case .pathTooLong(let p):               return "Socket path too long: \(p)"
        case .clientClosed:                     return "Client closed connection"
        case .headerTooLarge:                   return "Request header too large"
        case .malformedRequest(let m):          return "Malformed request: \(m)"
        case .writeFailed:                      return "Failed to write response"
        }
    }
}

extension JSONEncoder {
    static let bridge: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
