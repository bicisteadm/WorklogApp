import Foundation

/// Glues the raw HTTP server to the `AtlassianSession`. Knows about the three
/// endpoints the bridge exposes and translates between DTOs and session calls.
@MainActor
final class BridgeRouter {
    private let session: AtlassianSession
    private let settings: BridgeSettings

    init(session: AtlassianSession, settings: BridgeSettings) {
        self.session = session
        self.settings = settings
    }

    func handle(_ req: HTTPRequest) async -> HTTPResponse {
        switch (req.method, req.path) {
        case ("GET", "/health"):
            return health()
        case ("GET", "/services"):
            return services()
        case ("POST", "/fetch"):
            return await fetch(req)
        default:
            return .json(status: 404, body: ErrorResponseDTO(error: "Unknown endpoint \(req.method) \(req.path)"))
        }
    }

    // MARK: - Endpoints

    private func health() -> HTTPResponse {
        let dto: HealthResponseDTO
        switch session.state {
        case .unknown:
            dto = HealthResponseDTO(status: "unknown", displayName: nil, lastChecked: nil, message: nil)
        case .checking:
            dto = HealthResponseDTO(status: "checking", displayName: nil, lastChecked: nil, message: nil)
        case .connected(let name, let date):
            dto = HealthResponseDTO(status: "connected", displayName: name, lastChecked: date, message: nil)
        case .disconnected:
            dto = HealthResponseDTO(status: "disconnected", displayName: nil, lastChecked: nil,
                                    message: "Open the bridge app and sign in.")
        case .error(let msg):
            dto = HealthResponseDTO(status: "error", displayName: nil, lastChecked: nil, message: msg)
        }
        return .json(status: 200, body: dto)
    }

    private func services() -> HTTPResponse {
        let infos = settings.configuredServices.map { svc in
            ServicesResponseDTO.ServiceInfo(
                name: svc.name,
                baseURL: svc.url?.absoluteString,
                configured: svc.url != nil
            )
        }
        return .json(status: 200, body: ServicesResponseDTO(services: infos))
    }

    private func fetch(_ req: HTTPRequest) async -> HTTPResponse {
        let dto: FetchRequestDTO
        do {
            dto = try JSONDecoder().decode(FetchRequestDTO.self, from: req.body)
        } catch {
            return .json(status: 400, body: ErrorResponseDTO(error: "Invalid JSON body: \(error.localizedDescription)"))
        }

        // Before doing the actual fetch, make sure session is alive. If state is
        // unknown/disconnected, refuse with a clear message instead of attempting
        // a fetch that would silently hit the login page.
        if case .disconnected = session.state {
            return .json(status: 503, body: ErrorResponseDTO(error: "Session disconnected — sign in via the bridge app."))
        }
        if case .error(let m) = session.state {
            return .json(status: 503, body: ErrorResponseDTO(error: "Session error: \(m)"))
        }

        do {
            let result = try await session.fetch(
                service: dto.service,
                path: dto.path,
                method: dto.method ?? "GET",
                headers: dto.headers ?? [:],
                body: dto.body
            )
            let responseDTO = FetchResponseDTO(
                status: result.status,
                contentType: result.contentType,
                body: result.body
            )
            return .json(status: 200, body: responseDTO)
        } catch let err as AtlassianSession.FetchError {
            let code: Int
            switch err {
            case .unknownService, .invalidPath: code = 400
            case .notConfigured:                code = 503
            case .scriptError, .malformed:      code = 502
            }
            return .json(status: code, body: ErrorResponseDTO(error: err.errorDescription ?? "\(err)"))
        } catch {
            return .json(status: 500, body: ErrorResponseDTO(error: "\(error)"))
        }
    }
}
