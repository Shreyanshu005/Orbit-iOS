import Foundation

struct Envelope: Codable {
    let type: String
    var sessionId: String?
    let payload: String
    let timestamp: Int64
    
    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case payload
        case timestamp
    }
}

struct AuthRequest: Codable {
    let deviceName: String
    let deviceToken: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
        case deviceToken = "device_token"
    }
}

struct AuthResponse: Codable {
    let status: String
    let deviceToken: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case deviceToken = "device_token"
    }
}

/// Represents a request from the AI agent that requires user approval
struct AIApprovalRequest: Identifiable, Codable {
    let id: String
    let aiReasoning: String
    let proposedCommand: String
    let cwd: String
    let timestamp: String
    var status: String
}

/// Represents the response sent back to the daemon after user review
struct AIApprovalResponse: Codable {
    let requestId: String
    let action: ResponseAction
    
    enum ResponseAction: String, Codable {
        case approve
        case deny
    }
}

/// System statistics sent periodically from the macOS daemon
struct SystemStats: Codable {
    let cpuUsage: Double
    let memoryUsage: Double
    let uptime: TimeInterval
}
