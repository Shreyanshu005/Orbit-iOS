import Foundation
import Combine
import UIKit

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    
    @Published var isConnected = false
    @Published var isAuthenticated = false
    @Published var pendingApprovals: [AIApprovalRequest] = []
    
    // Publisher for PTY data
    let ptyDataPublisher = PassthroughSubject<Data, Never>()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    
    var hostUrl: String = "ws://192.168.31.55:8081/ws/ios"
    private var currentSessionId: String = ""
    
    // UserDefaults Keys
    private let kSavedMacID = "saved_mac_id"
    private let kDeviceToken = "device_token"
    
    var hasSavedMac: Bool {
        return UserDefaults.standard.string(forKey: kSavedMacID) != nil
    }
    
    private init() {}
    
    func connect(pairingCode: String? = nil) {
        guard let url = URL(string: hostUrl) else { return }
        
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        
        isConnected = true
        if let task = webSocketTask {
            receiveMessage(for: task)
        }
        
        // Initiate Relay connection
        if let code = pairingCode, !code.isEmpty {
            sendEnvelope(type: "ios_pair", payload: code)
        } else if let macId = UserDefaults.standard.string(forKey: kSavedMacID) {
            sendEnvelope(type: "ios_reconnect", payload: macId)
        } else {
            disconnect()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        DispatchQueue.main.async {
            self.isConnected = false
            self.isAuthenticated = false
            self.currentSessionId = ""
        }
    }
    
    private func sendEnvelope(type: String, payload: String) {
        let env = Envelope(
            type: type,
            sessionId: currentSessionId.isEmpty ? nil : currentSessionId,
            payload: payload,
            timestamp: Int64(Date().timeIntervalSince1970)
        )
        guard let data = try? JSONEncoder().encode(env),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { error in
            if let error = error { print("Send error: \(error)") }
        }
    }
    
    func sendPtyData(_ data: Data) {
        let base64String = data.base64EncodedString()
        sendEnvelope(type: "pty_input", payload: base64String)
    }
    
    func sendTask(_ task: String) {
        sendEnvelope(type: "ai_task", payload: task)
    }
    
    func sendResize(cols: Int, rows: Int) {
        let payloadDict: [String: Int] = ["cols": cols, "rows": rows]
        guard let data = try? JSONEncoder().encode(payloadDict),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        sendEnvelope(type: "pty_resize", payload: jsonString)
    }
    
    func sendApprovalResponse(requestId: String, isApproved: Bool) {
        let response = AIApprovalResponse(requestId: requestId, action: isApproved ? .approve : .deny)
        guard let data = try? JSONEncoder().encode(response),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        sendEnvelope(type: "ai_response", payload: jsonString)
        
        DispatchQueue.main.async {
            self.pendingApprovals.removeAll { $0.id == requestId }
        }
    }
    
    private func receiveMessage(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            // Prevent cancelled tasks from killing the active connection
            guard self?.webSocketTask == task else { return }
            
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.disconnect()
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleIncomingEnvelope(text)
                case .data(_):
                    // We expect strictly JSON Envelopes now, no raw binary
                    break
                @unknown default:
                    break
                }
                self?.receiveMessage(for: task)
            }
        }
    }
    
    private func handleIncomingEnvelope(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        
        switch env.type {
        case "error":
            print("Relay Error: \(env.payload)")
            disconnect()
            
        case "session_started":
            self.currentSessionId = env.sessionId ?? ""
            
            // Parse payload
            if let data = env.payload.data(using: .utf8),
               let payloadDict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                
                if let macId = payloadDict["mac_id"] {
                    UserDefaults.standard.set(macId, forKey: kSavedMacID)
                }
                
                if let localIp = payloadDict["local_ip"], !localIp.isEmpty {
                    print("Received local IP: \(localIp). Attempting P2P connection...")
                    self.connectToLocal(ip: localIp)
                }
            } else if !env.payload.isEmpty {
                // Fallback for old payload format
                UserDefaults.standard.set(env.payload, forKey: kSavedMacID)
            }
            
            // Send Auth Request to Mac
            let token = UserDefaults.standard.string(forKey: kDeviceToken)
            let authReq = AuthRequest(deviceName: UIDevice.current.name, deviceToken: token)
            if let reqData = try? JSONEncoder().encode(authReq),
               let reqStr = String(data: reqData, encoding: .utf8) {
                sendEnvelope(type: "auth_request", payload: reqStr)
            }
            
        case "auth_response":
            guard let respData = env.payload.data(using: .utf8),
                  let authResp = try? JSONDecoder().decode(AuthResponse.self, from: respData) else { return }
            
            if authResp.status == "approved" {
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                }
                if let newToken = authResp.deviceToken {
                    UserDefaults.standard.set(newToken, forKey: kDeviceToken)
                }
            } else {
                print("Auth Rejected")
                disconnect()
            }
            
        case "pty_stream":
            if let decodedData = Data(base64Encoded: env.payload) {
                ptyDataPublisher.send(decodedData)
            }
            
        case "ai_request":
            if let reqData = env.payload.data(using: .utf8),
               let approvalReq = try? JSONDecoder().decode(AIApprovalRequest.self, from: reqData) {
                DispatchQueue.main.async {
                    self.pendingApprovals.append(approvalReq)
                }
            }
            
        default:
            break
        }
    }
    
    func clearSavedDevice() {
        UserDefaults.standard.removeObject(forKey: kSavedMacID)
        UserDefaults.standard.removeObject(forKey: kDeviceToken)
    }
    
    private func connectToLocal(ip: String) {
        let localUrlStr = "ws://\(ip):8082/ws/local"
        guard let url = URL(string: localUrlStr) else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0 // Fast timeout for local network
        
        let localTask = urlSession.webSocketTask(with: request)
        localTask.resume()
        
        let authEnv = Envelope(
            type: "local_auth",
            sessionId: self.currentSessionId,
            payload: "",
            timestamp: Int64(Date().timeIntervalSince1970)
        )
        guard let data = try? JSONEncoder().encode(authEnv),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        localTask.send(message) { [weak self] error in
            if let error = error {
                print("Local P2P fallback failed: \(error). Continuing with Relay.")
                localTask.cancel(with: .normalClosure, reason: nil)
            } else {
                print("⚡️ Successfully sent local_auth! Swapping to Local WebSocket P2P mode.")
                DispatchQueue.main.async {
                    self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                    self?.webSocketTask = localTask
                    self?.isAuthenticated = true // Automatically authenticated on Local network!
                    self?.receiveMessage(for: localTask)
                    
                    // Force the Mac terminal to print a fresh prompt
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.sendPtyData(Data([0x0D])) // Send 'Enter' keystroke
                    }
                }
            }
        }
    }
}
