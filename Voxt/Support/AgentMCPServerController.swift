import Foundation
import Network
import AVFoundation
import Combine

@MainActor
final class AgentMCPServerController: ObservableObject {
    private struct ServerConfiguration: Equatable {
        let isEnabled: Bool
        let openAtLaunch: Bool
        let port: UInt16
    }

    private enum EndpointProbeResult {
        case voxtMCP
        case unexpectedResponse(statusCode: Int?)
        case transportError(String)
    }

    enum RuntimeStatus: Equatable {
        case stopped
        case starting
        case running
        case portInUse
        case permissionBlocked(String)
        case failed(String)
    }

    @Published private(set) var runtimeStatus: RuntimeStatus = .stopped
    @Published private(set) var endpointURLString = AgentMCPServerController.endpointURLString(for: 51090)
    @Published private(set) var lastStatusMessage = ""

    weak var appDelegate: AppDelegate?

    private let listenerQueue = DispatchQueue(label: "Voxt.AgentMCPServer")
    private var listener: NWListener?
    private var defaultsObserver: NSObjectProtocol?
    private var activePort: UInt16?
    private var activeConnectionHandlers: [UUID: HTTPConnectionHandler] = [:]
    private var lastObservedConfiguration: ServerConfiguration?
    private var portConflictProbeTask: Task<Void, Never>?

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyConfigurationFromDefaults()
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        listener?.cancel()
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.agentMCPEnabled)
    }

    var openAtLaunch: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.agentMCPOpenAtLaunch) as? Bool ?? true
    }

    var configuredPort: Int {
        let raw = UserDefaults.standard.integer(forKey: AppPreferenceKey.agentMCPPort)
        let fallback = 51090
        let resolved = raw == 0 ? fallback : raw
        return min(max(resolved, 1024), 65535)
    }

    var displayStatusTitle: String {
        switch displayStatus {
        case .stopped:
            return AppLocalization.localizedString("Stopped")
        case .starting:
            return AppLocalization.localizedString("Starting")
        case .running:
            return AppLocalization.localizedString("Running")
        case .portInUse:
            return AppLocalization.localizedString("Port in Use")
        case .permissionBlocked:
            return AppLocalization.localizedString("Permission Blocked")
        case .failed:
            return AppLocalization.localizedString("Error")
        }
    }

    var displayStatusDetail: String {
        switch displayStatus {
        case .stopped:
            return AppLocalization.localizedString("The local MCP endpoint is not running.")
        case .starting:
            return AppLocalization.localizedString("Starting the local MCP endpoint.")
        case .running:
            return AppLocalization.localizedString("Ready for Claude Code and Codex to connect.")
        case .portInUse:
            if !lastStatusMessage.isEmpty {
                return lastStatusMessage
            }
            return AppLocalization.localizedString("The configured port is already occupied by another process.")
        case .permissionBlocked(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    var claudeCommand: String {
        "claude mcp add --transport http voxt \(endpointURLString)"
    }

    var codexCommand: String {
        "codex mcp add voxt --url \(endpointURLString)"
    }

    func attach(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func applyConfigurationOnLaunch() {
        endpointURLString = Self.endpointURLString(for: configuredPort)
        let configuration = currentConfiguration()
        lastObservedConfiguration = configuration
        if configuration.isEnabled && configuration.openAtLaunch {
            startServer()
        } else {
            stopServer()
        }
    }

    func applyConfigurationFromDefaults() {
        endpointURLString = Self.endpointURLString(for: configuredPort)
        let configuration = currentConfiguration()
        if lastObservedConfiguration == configuration {
            return
        }
        lastObservedConfiguration = configuration

        guard configuration.isEnabled else {
            stopServer()
            return
        }

        if activePort == configuration.port {
            switch runtimeStatus {
            case .starting, .running, .portInUse, .permissionBlocked, .failed:
                return
            case .stopped:
                break
            }
        }

        if runtimeStatus == .running, activePort == configuration.port {
            return
        }

        startServer()
    }

    func stopServer() {
        portConflictProbeTask?.cancel()
        portConflictProbeTask = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        cancelActiveConnectionHandlers()
        activePort = nil
        runtimeStatus = .stopped
        lastStatusMessage = ""
    }

    func testConnection() async -> String {
        guard isEnabled else {
            return AppLocalization.localizedString("Enable the MCP server before testing the connection.")
        }

        guard let url = URL(string: endpointURLString) else {
            return AppLocalization.localizedString("The local MCP endpoint URL is invalid.")
        }

        switch await probeEndpoint(at: url) {
        case .voxtMCP:
            return AppLocalization.localizedString("Connection test succeeded.")
        case .unexpectedResponse(let statusCode):
            if let statusCode {
                return AppLocalization.format(
                    "Connection test reached this port, but the response did not match Voxt MCP (HTTP %d).",
                    statusCode
                )
            }
            return AppLocalization.localizedString("Connection test reached this port, but the response did not match Voxt MCP.")
        case .transportError(let message):
            return AppLocalization.format("Connection test failed: %@", message)
        }
    }

    func refreshStatus() async {
        endpointURLString = Self.endpointURLString(for: configuredPort)
        lastObservedConfiguration = currentConfiguration()

        guard isEnabled else {
            stopServer()
            return
        }

        startServer()

        try? await Task.sleep(for: .milliseconds(350))
        guard case .portInUse = runtimeStatus else {
            return
        }

        await updatePortConflictStatusDetail()
    }

    private var displayStatus: DisplayStatus {
        switch runtimeStatus {
        case .portInUse:
            return .portInUse
        case .permissionBlocked(let message):
            return .permissionBlocked(message)
        case .failed(let message):
            return .failed(message)
        case .running where AVCaptureDevice.authorizationStatus(for: .audio) != .authorized:
            return .permissionBlocked(
                AppLocalization.localizedString("Microphone permission is required before agent answers can be recorded.")
            )
        case .running:
            return .running
        case .starting:
            return .starting
        case .stopped:
            return .stopped
        }
    }

    private func startServer() {
        portConflictProbeTask?.cancel()
        portConflictProbeTask = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        runtimeStatus = .starting
        lastStatusMessage = ""

        let portValue = UInt16(configuredPort)
        activePort = portValue
        guard let endpointPort = NWEndpoint.Port(rawValue: portValue) else {
            runtimeStatus = .failed(AppLocalization.localizedString("The configured MCP port is invalid."))
            lastStatusMessage = AppLocalization.localizedString("The configured MCP port is invalid.")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: endpointPort)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] (connection: NWConnection) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let handlerID = UUID()
                    let handler = HTTPConnectionHandler(
                        connection: connection,
                        controller: self,
                        onComplete: { [weak self] in
                            Task { @MainActor [weak self] in
                                self?.removeActiveConnectionHandler(id: handlerID)
                            }
                        }
                    )
                    self.activeConnectionHandlers[handlerID] = handler
                    handler.start(on: self.listenerQueue)
                }
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            let resolvedMessage = Self.userFacingMessage(for: error)
            if Self.isPermissionBlocked(error) {
                runtimeStatus = .permissionBlocked(resolvedMessage)
            } else {
                runtimeStatus = .failed(resolvedMessage)
            }
            lastStatusMessage = resolvedMessage
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .setup:
            portConflictProbeTask?.cancel()
            portConflictProbeTask = nil
            runtimeStatus = .starting
        case .waiting(let error):
            if Self.isPortInUse(error) {
                runtimeStatus = .portInUse
                lastStatusMessage = ""
                schedulePortConflictProbe()
            } else if Self.isPermissionBlocked(error) {
                portConflictProbeTask?.cancel()
                portConflictProbeTask = nil
                let resolvedMessage = Self.userFacingMessage(for: error)
                runtimeStatus = .permissionBlocked(resolvedMessage)
                lastStatusMessage = resolvedMessage
            } else {
                portConflictProbeTask?.cancel()
                portConflictProbeTask = nil
                let resolvedMessage = Self.userFacingMessage(for: error)
                runtimeStatus = .failed(resolvedMessage)
                lastStatusMessage = resolvedMessage
            }
        case .ready:
            portConflictProbeTask?.cancel()
            portConflictProbeTask = nil
            runtimeStatus = .running
            lastStatusMessage = ""
        case .failed(let error):
            if Self.isPortInUse(error) {
                runtimeStatus = .portInUse
                lastStatusMessage = ""
                schedulePortConflictProbe()
            } else if Self.isPermissionBlocked(error) {
                portConflictProbeTask?.cancel()
                portConflictProbeTask = nil
                let resolvedMessage = Self.userFacingMessage(for: error)
                runtimeStatus = .permissionBlocked(resolvedMessage)
                lastStatusMessage = resolvedMessage
            } else {
                portConflictProbeTask?.cancel()
                portConflictProbeTask = nil
                let resolvedMessage = Self.userFacingMessage(for: error)
                runtimeStatus = .failed(resolvedMessage)
                lastStatusMessage = resolvedMessage
            }
            listener?.cancel()
            listener = nil
            cancelActiveConnectionHandlers()
        case .cancelled:
            portConflictProbeTask?.cancel()
            portConflictProbeTask = nil
            listener = nil
            cancelActiveConnectionHandlers()
            activePort = nil
            switch runtimeStatus {
            case .portInUse, .permissionBlocked, .failed:
                break
            default:
                runtimeStatus = .stopped
                lastStatusMessage = ""
            }
        default:
            break
        }
    }

    fileprivate func handleHTTPRequest(_ request: HTTPConnectionHandler.HTTPRequest) async -> HTTPConnectionHandler.HTTPResponse {
        guard request.path == "/mcp" else {
            return .plain(statusCode: 404, body: "Not Found")
        }

        switch request.method {
        case "POST":
            return await handlePOST(request)
        case "GET":
            return .plain(statusCode: 405, body: "GET is not supported by this MCP endpoint.")
        case "DELETE":
            return .plain(statusCode: 405, body: "DELETE is not supported by this MCP endpoint.")
        default:
            return .plain(statusCode: 405, body: "Method Not Allowed")
        }
    }

    private func handlePOST(_ request: HTTPConnectionHandler.HTTPRequest) async -> HTTPConnectionHandler.HTTPResponse {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: request.body) else {
            return makeProtocolErrorResponse(id: nil, code: -32700, message: "Parse error")
        }

        if let messages = jsonObject as? [Any] {
            var responses: [[String: Any]] = []
            for message in messages {
                guard let dict = message as? [String: Any] else { continue }
                if let response = await handleMessage(dict) {
                    responses.append(response)
                }
            }
            if responses.isEmpty {
                return .empty(statusCode: 202)
            }
            return .json(statusCode: 200, object: responses)
        }

        guard let message = jsonObject as? [String: Any] else {
            return makeProtocolErrorResponse(id: nil, code: -32600, message: "Invalid Request")
        }

        guard let response = await handleMessage(message) else {
            return .empty(statusCode: 202)
        }
        return .json(statusCode: 200, object: response)
    }

    private func handleMessage(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""

        switch method {
        case "initialize":
            return [
                "jsonrpc": "2.0",
                "id": id as Any,
                "result": [
                    "protocolVersion": "2025-03-26",
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "voxt",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    ]
                ]
            ]
        case "notifications/initialized":
            return nil
        case "ping":
            return [
                "jsonrpc": "2.0",
                "id": id as Any,
                "result": [:]
            ]
        case "tools/list":
            return [
                "jsonrpc": "2.0",
                "id": id as Any,
                "result": [
                    "tools": [
                        Self.askUserVoiceToolDefinition
                    ]
                ]
            ]
        case "tools/call":
            return await handleToolsCall(message: message, id: id)
        default:
            return makeProtocolErrorObject(id: id, code: -32601, message: "Method not found")
        }
    }

    private func handleToolsCall(message: [String: Any], id: Any?) async -> [String: Any] {
        guard let params = message["params"] as? [String: Any],
              let name = params["name"] as? String else {
            return makeProtocolErrorObject(id: id, code: -32602, message: "Invalid params")
        }

        guard name == "ask_user_voice" else {
            return makeToolCallResponse(id: id, payload: AgentPromptToolResponse.error(.invalidRequest, message: "Unknown tool."))
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let rawQuestions = arguments["questions"] as? [String] ?? []
        let questions = rawQuestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !questions.isEmpty else {
            return makeToolCallResponse(id: id, payload: AgentPromptToolResponse.error(.invalidRequest, message: "questions must contain at least one non-empty string."))
        }

        let timeoutSeconds = min(max(arguments["timeout_sec"] as? Double ?? 180, 5), 900)
        let contextHint = (arguments["context_hint"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let appDelegate else {
            return makeToolCallResponse(id: id, payload: AgentPromptToolResponse.error(.serverDisabled, message: "Voxt is not ready to accept agent prompts."))
        }

        let response = await appDelegate.handleAgentMCPAskUserVoice(
            request: AgentPromptRequest(
                id: UUID(),
                questions: questions,
                contextHint: contextHint?.isEmpty == true ? nil : contextHint,
                timeoutSeconds: timeoutSeconds
            )
        )
        return makeToolCallResponse(id: id, payload: response)
    }

    private func makeToolCallResponse(id: Any?, payload: AgentPromptToolResponse) -> [String: Any] {
        let structuredContent = payload.responsePayload
        let serializedText: String
        if let data = try? JSONSerialization.data(withJSONObject: structuredContent, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            serializedText = text
        } else {
            serializedText = payload.transcript
        }

        return [
            "jsonrpc": "2.0",
            "id": id as Any,
            "result": [
                "content": [
                    [
                        "type": "text",
                        "text": serializedText
                    ]
                ],
                "structuredContent": structuredContent,
                "isError": payload.status == "error"
            ]
        ]
    }

    private func makeProtocolErrorResponse(id: Any?, code: Int, message: String) -> HTTPConnectionHandler.HTTPResponse {
        .json(
            statusCode: 200,
            object: makeProtocolErrorObject(id: id, code: code, message: message)
        )
    }

    private func makeProtocolErrorObject(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id as Any,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    static var askUserVoiceToolDefinition: [String: Any] {
        [
            "name": "ask_user_voice",
            "description": "Ask the local Voxt user one or more questions by voice. Use this when you need clarification from the human and want them to answer by speaking instead of typing.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "questions": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Questions to display in the Voxt prompt panel."
                    ],
                    "context_hint": [
                        "type": "string",
                        "description": "Optional short context shown below the title before recording starts."
                    ],
                    "timeout_sec": [
                        "type": "number",
                        "description": "Optional timeout in seconds. Defaults to 180 seconds."
                    ]
                ],
                "required": ["questions"]
            ]
        ]
    }

    static func endpointURLString(for port: Int) -> String {
        "http://127.0.0.1:\(port)/mcp"
    }

    private static func isPortInUse(_ error: NWError) -> Bool {
        if case .posix(let posixError) = error {
            return posixError == .EADDRINUSE
        }
        return false
    }

    private enum DisplayStatus: Equatable {
        case stopped
        case starting
        case running
        case portInUse
        case permissionBlocked(String)
        case failed(String)
    }

    private static func isPermissionBlocked(_ error: Error) -> Bool {
        if let networkError = error as? NWError {
            if case .posix(let posixError) = networkError {
                return posixError == .EPERM || posixError == .EACCES
            }
        }
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain &&
            (nsError.code == Int(EPERM) || nsError.code == Int(EACCES))
    }

    private static func userFacingMessage(for error: Error) -> String {
        if isPermissionBlocked(error) {
            return AppLocalization.localizedString(
                "Voxt could not start the local MCP server because this build is missing permission to accept incoming localhost connections. Rebuild or reinstall with the App Sandbox Incoming Connections (Server) entitlement enabled."
            )
        }
        return error.localizedDescription
    }

    private static func makeDirectLocalSession(configuration: URLSessionConfiguration) -> URLSession {
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            kCFNetworkProxiesHTTPProxy as String: "",
            kCFNetworkProxiesHTTPPort as String: 0,
            kCFNetworkProxiesHTTPSProxy as String: "",
            kCFNetworkProxiesHTTPSPort as String: 0,
            kCFNetworkProxiesSOCKSProxy as String: "",
            kCFNetworkProxiesSOCKSPort as String: 0,
            kCFNetworkProxiesProxyAutoConfigURLString as String: "",
            kCFNetworkProxiesExceptionsList as String: [],
            kCFNetworkProxiesExcludeSimpleHostnames as String: false
        ]
        configuration.proxyConfigurations = []
        return URLSession(configuration: configuration)
    }

    private func removeActiveConnectionHandler(id: UUID) {
        activeConnectionHandlers[id] = nil
    }

    private func cancelActiveConnectionHandlers() {
        let handlers = activeConnectionHandlers.values
        activeConnectionHandlers.removeAll()
        handlers.forEach { $0.cancel() }
    }

    private func currentConfiguration() -> ServerConfiguration {
        ServerConfiguration(
            isEnabled: isEnabled,
            openAtLaunch: openAtLaunch,
            port: UInt16(configuredPort)
        )
    }

    private func schedulePortConflictProbe() {
        portConflictProbeTask?.cancel()
        portConflictProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updatePortConflictStatusDetail()
        }
    }

    private func updatePortConflictStatusDetail() async {
        guard case .portInUse = runtimeStatus else { return }
        guard let url = URL(string: endpointURLString) else {
            lastStatusMessage = AppLocalization.localizedString("The configured port is already occupied by another process.")
            return
        }

        switch await probeEndpoint(at: url) {
        case .voxtMCP:
            lastStatusMessage = AppLocalization.localizedString(
                "This port is already serving a Voxt MCP endpoint, likely from another Voxt instance. Close the other instance, then click Refresh, or choose a different port."
            )
        case .unexpectedResponse:
            lastStatusMessage = AppLocalization.localizedString(
                "The configured port is already occupied by another local service. Stop that service or choose a different port."
            )
        case .transportError:
            lastStatusMessage = AppLocalization.localizedString(
                "The configured port is already occupied by another process. Close the app using this port, then click Refresh, or choose a different port."
            )
        }
    }

    private func probeEndpoint(at url: URL) async -> EndpointProbeResult {
        let request = Self.makeInitializeRequest(url: url)

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            configuration.waitsForConnectivity = false
            let session = Self.makeDirectLocalSession(configuration: configuration)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .transportError(AppLocalization.localizedString("Missing HTTP response."))
            }

            guard httpResponse.statusCode == 200 else {
                return .unexpectedResponse(statusCode: httpResponse.statusCode)
            }

            guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = jsonObject["result"] as? [String: Any],
                  let serverInfo = result["serverInfo"] as? [String: Any],
                  let name = serverInfo["name"] as? String,
                  name.caseInsensitiveCompare("voxt") == .orderedSame
            else {
                return .unexpectedResponse(statusCode: httpResponse.statusCode)
            }

            return .voxtMCP
        } catch {
            return .transportError(error.localizedDescription)
        }
    }

    private static func makeInitializeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "Voxt Settings",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                ]
            ]
        ])
        return request
    }
}

private final class HTTPConnectionHandler {
    struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct HTTPResponse {
        let statusCode: Int
        let body: Data
        let headers: [String: String]

        static func json(statusCode: Int, object: Any) -> Self {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
            return Self(
                statusCode: statusCode,
                body: data,
                headers: [
                    "Content-Type": "application/json; charset=utf-8"
                ]
            )
        }

        static func plain(statusCode: Int, body: String) -> Self {
            Self(
                statusCode: statusCode,
                body: Data(body.utf8),
                headers: [
                    "Content-Type": "text/plain; charset=utf-8"
                ]
            )
        }

        static func empty(statusCode: Int) -> Self {
            Self(statusCode: statusCode, body: Data(), headers: [:])
        }
    }

    private let connection: NWConnection
    private weak var controller: AgentMCPServerController?
    private let onComplete: () -> Void
    private var buffer = Data()
    private var didFinish = false

    init(
        connection: NWConnection,
        controller: AgentMCPServerController?,
        onComplete: @escaping () -> Void
    ) {
        self.connection = connection
        self.controller = controller
        self.onComplete = onComplete
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNextChunk()
    }

    func cancel() {
        connection.cancel()
        finish()
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                if let request = self.parseRequest() {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let response: HTTPResponse
                        if let controller = self.controller {
                            response = await controller.handleHTTPRequest(request)
                        } else {
                            response = .plain(statusCode: 503, body: "Service Unavailable")
                        }
                        self.send(response)
                    }
                    return
                }
            }

            if isComplete || error != nil {
                self.send(.plain(statusCode: 400, body: "Bad Request"))
                return
            }

            self.receiveNextChunk()
        }
    }

    private func parseRequest() -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            return nil
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        guard buffer.count >= bodyStart + contentLength else {
            return nil
        }

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(
            method: parts[0].uppercased(),
            path: parts[1],
            headers: headers,
            body: body
        )
    }

    private func send(_ response: HTTPResponse) {
        let statusText = Self.statusText(for: response.statusCode)
        var headerLines = [
            "HTTP/1.1 \(response.statusCode) \(statusText)",
            "Content-Length: \(response.body.count)",
            "Connection: close"
        ]
        for (name, value) in response.headers {
            headerLines.append("\(name): \(value)")
        }
        headerLines.append("")
        headerLines.append("")

        var payload = Data(headerLines.joined(separator: "\r\n").utf8)
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
            self?.finish()
        })
    }

    private static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        connection.stateUpdateHandler = nil
        onComplete()
    }
}
