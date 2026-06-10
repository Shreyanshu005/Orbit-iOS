package protocol

import "time"

const (
	TypePTYStream    = "pty_stream"
	TypePTYInput     = "pty_input"
	TypePTYResize    = "pty_resize"
	TypeAIRequest    = "ai_request"
	TypeAIResponse   = "ai_response"
	TypeAuthRequest  = "auth_request"
	TypeAuthResponse = "auth_response"
)

// Envelope is the standard wrapper for all websocket messages.
type Envelope struct {
	Type      string `json:"type"`
	SessionID string `json:"session_id,omitempty"`
	Payload   string `json:"payload"` // JSON encoded string or Base64 encoded bytes
	Timestamp int64  `json:"timestamp"`
}

// AuthRequest is sent by Termy to authenticate.
type AuthRequest struct {
	DeviceName  string `json:"device_name"`
	DeviceToken string `json:"device_token,omitempty"` // Empty if first time pairing
}

// AuthResponse is sent by orbitd after user approves/rejects.
type AuthResponse struct {
	Status      string `json:"status"` // "approved", "rejected", "pending"
	DeviceToken string `json:"device_token,omitempty"`
}

// AIApprovalRequest represents a command proposed by the AI that needs user approval.
type AIApprovalRequest struct {
	ID              string    `json:"id"`
	AIReasoning     string    `json:"aiReasoning"`
	ProposedCommand string    `json:"proposedCommand"`
	CWD             string    `json:"cwd"`
	Timestamp       time.Time `json:"timestamp"`
	Status          string    `json:"status"`
}

// AIApprovalResponse is the reply sent from the iOS client.
type AIApprovalResponse struct {
	RequestID string `json:"requestId"`
	Action    string `json:"action"` // "approve" or "deny"
}

// SystemStats represents basic machine health to display on the client.
type SystemStats struct {
	CPUUsage    float64 `json:"cpuUsage"`
	MemoryUsage float64 `json:"memoryUsage"`
	Uptime      float64 `json:"uptime"`
}
