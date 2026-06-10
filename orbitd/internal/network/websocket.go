package network

import (
	"bufio"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"
	"net"

	"github.com/gorilla/websocket"
	"github.com/orbit/orbitd/internal/agent"
	"github.com/orbit/orbitd/internal/approval"
	"github.com/orbit/orbitd/internal/pty"
	"github.com/orbit/orbitd/pkg/protocol"
)

type RelayClient struct {
	queueMgr *approval.QueueManager
	ptyMgr   *pty.PTYManager
	orch     *agent.Orchestrator
	conn     *websocket.Conn
	macID    string
}

func NewRelayClient(queueMgr *approval.QueueManager, ptyMgr *pty.PTYManager, orch *agent.Orchestrator) *RelayClient {
	return &RelayClient{
		queueMgr: queueMgr,
		ptyMgr:   ptyMgr,
		orch:     orch,
	}
}

func (c *RelayClient) Connect(url string) error {
	log.Printf("Connecting to Relay Server at %s...", url)
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		return err
	}
	// 1. Send mac_register (backwards compatible blank payload)
	c.sendEnvelope("mac_register", "", "")

	// 2. Wait for mac_registered
	var env protocol.Envelope
	if err := conn.ReadJSON(&env); err != nil {
		return err
	}
	
	if env.Type == "mac_registered" {
		var payload map[string]string
		json.Unmarshal([]byte(env.Payload), &payload)
		c.macID = payload["mac_id"]
		code := payload["code"]

		log.Printf("\n============================================\n")
		log.Printf("📱 OPEN TERMY ON YOUR IPHONE TO CONNECT\n")
		log.Printf("🔑 PAIRING CODE: %s\n", code)
		log.Printf("============================================\n\n")
	}

	// 3. Send Local IP asynchronously (old relay ignores this, new relay catches it)
	localIP := GetLocalIP()
	if localIP != "" {
		c.sendEnvelope("register_local_ip", "", localIP)
	}

	go c.writePump()
	go c.readPump()

	return nil
}

func (c *RelayClient) sendEnvelope(msgType, sessionID, payload string) {
	env := protocol.Envelope{
		Type:      msgType,
		SessionID: sessionID,
		Payload:   payload,
		Timestamp: time.Now().Unix(),
	}
	c.conn.WriteJSON(env)
}

func (c *RelayClient) readPump() {
	defer c.conn.Close()
	for {
		var env protocol.Envelope
		if err := c.conn.ReadJSON(&env); err != nil {
			log.Println("Relay connection closed:", err)
			break
		}

		switch env.Type {
		case protocol.TypeAuthRequest:
			c.handleAuthRequest(env)
		case "ai_task":
			go c.orch.HandleTask(env.Payload)
		case protocol.TypePTYInput:
			data, err := base64.StdEncoding.DecodeString(env.Payload)
			if err == nil {
				c.ptyMgr.Write(data)
			}
		case protocol.TypePTYResize:
			var size struct {
				Cols int `json:"cols"`
				Rows int `json:"rows"`
			}
			if err := json.Unmarshal([]byte(env.Payload), &size); err == nil {
				c.ptyMgr.Resize(size.Cols, size.Rows)
			}
		case protocol.TypeAIResponse:
			var resp protocol.AIApprovalResponse
			if err := json.Unmarshal([]byte(env.Payload), &resp); err == nil {
				c.queueMgr.ResolveRequest(resp)
			}
		}
	}
}

func (c *RelayClient) handleAuthRequest(env protocol.Envelope) {
	var authReq protocol.AuthRequest
	json.Unmarshal([]byte(env.Payload), &authReq)

	tokens := loadTrustedDevices()
	isTrusted := false

	// Check if token matches
	if authReq.DeviceToken != "" {
		for _, t := range tokens {
			if t == authReq.DeviceToken {
				isTrusted = true
				break
			}
		}
	}

	if !isTrusted {
		var input string
		if os.Getenv("ORBIT_GUI_MODE") == "1" {
			script := fmt.Sprintf(`display dialog "Allow connection from iPhone '%s'?" buttons {"Deny", "Allow"} default button "Allow" with icon caution with title "Orbit Security"`, authReq.DeviceName)
			out, err := exec.Command("osascript", "-e", script).Output()
			if err == nil && strings.Contains(string(out), "button returned:Allow") {
				input = "y"
			} else {
				input = "n"
			}
		} else {
			// Prompt user on Mac stdout
			fmt.Printf("\n🔒 [SECURITY] Allow connection from '%s'? [y/N]: ", authReq.DeviceName)
			reader := bufio.NewReader(os.Stdin)
			input, _ = reader.ReadString('\n')
			input = strings.TrimSpace(strings.ToLower(input))
		}

		if input == "y" || input == "yes" {
			// Generate new token
			b := make([]byte, 16)
			rand.Read(b)
			newToken := hex.EncodeToString(b)
			saveTrustedDevice(newToken)

			respPayload, _ := json.Marshal(protocol.AuthResponse{
				Status:      "approved",
				DeviceToken: newToken,
			})
			c.sendEnvelope(protocol.TypeAuthResponse, env.SessionID, string(respPayload))
			log.Println("✅ Device trusted and connected.")
		} else {
			respPayload, _ := json.Marshal(protocol.AuthResponse{Status: "rejected"})
			c.sendEnvelope(protocol.TypeAuthResponse, env.SessionID, string(respPayload))
			log.Println("🚫 Connection rejected.")
		}
	} else {
		log.Printf("✅ Trusted device reconnected: %s", authReq.DeviceName)
		respPayload, _ := json.Marshal(protocol.AuthResponse{Status: "approved"})
		c.sendEnvelope(protocol.TypeAuthResponse, env.SessionID, string(respPayload))
	}
}

func (c *RelayClient) writePump() {
	ptyStream := c.ptyMgr.Subscribe()
	approvalStream := c.queueMgr.Subscribe()

	for {
		select {
		case data, ok := <-ptyStream:
			if !ok {
				return
			}
			// Base64 encode raw bytes
			payload := base64.StdEncoding.EncodeToString(data)
			// Broadcast PTY to ALL active sessions (Relay will route if SessionID is empty or we can track it)
			// For MVP, if we leave SessionID empty, relay might drop it, so we should really track active sessions.
			// To keep it simple, we will just send it with an empty SessionID and update relay to broadcast it.
			c.sendEnvelope(protocol.TypePTYStream, "", payload)

		case req, ok := <-approvalStream:
			if !ok {
				return
			}
			b, err := json.Marshal(req)
			if err == nil {
				c.sendEnvelope(protocol.TypeAIRequest, "", string(b))
			}
		}
	}
}

// Minimal JSON storage for trusted devices
func loadTrustedDevices() []string {
	b, err := os.ReadFile("trusted_devices.json")
	if err != nil {
		return []string{}
	}
	var tokens []string
	json.Unmarshal(b, &tokens)
	return tokens
}

func saveTrustedDevice(token string) {
	tokens := loadTrustedDevices()
	tokens = append(tokens, token)
	b, _ := json.Marshal(tokens)
	os.WriteFile("trusted_devices.json", b, 0600)
}

func GetLocalIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ""
	}
	for _, address := range addrs {
		if ipnet, ok := address.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP.String()
			}
		}
	}
	return ""
}
