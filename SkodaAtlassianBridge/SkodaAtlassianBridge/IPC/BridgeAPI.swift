import Foundation

/// Request/response shapes for the local HTTP-over-Unix-socket API. The
/// bridge exposes a single endpoint `POST /fetch` plus health/info endpoints
/// (`GET /health`, `GET /services`).
///
/// Wire format is plain HTTP/1.1 with JSON bodies — easy to consume from any
/// language without special SDKs.

struct FetchRequestDTO: Decodable {
    let service: String
    let path: String
    let method: String?
    let headers: [String: String]?
    let body: String?
}

struct FetchResponseDTO: Encodable {
    let status: Int
    let contentType: String
    let body: String
}

struct ErrorResponseDTO: Encodable {
    let error: String
}

struct HealthResponseDTO: Encodable {
    let status: String           // "connected" | "disconnected" | "unknown" | "checking" | "error"
    let displayName: String?
    let lastChecked: Date?
    let message: String?
}

struct ServicesResponseDTO: Encodable {
    struct ServiceInfo: Encodable {
        let name: String
        let baseURL: String?
        let configured: Bool
    }
    let services: [ServiceInfo]
}
