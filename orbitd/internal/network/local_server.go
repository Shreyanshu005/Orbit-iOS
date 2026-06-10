package network

import (
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
	"github.com/orbit/orbitd/internal/agent"
	"github.com/orbit/orbitd/internal/approval"
	"github.com/orbit/orbitd/internal/pty"
	"github.com/orbit/orbitd/pkg/protocol"
)

type LocalServer struct {
	queueMgr *approval.QueueManager
	ptyMgr   *pty.PTYManager
	orch     *agent.Orchestrator
	upgrader websocket.Upgrader
}

func NewLocalServer(queueMgr *approval.QueueManager, ptyMgr *pty.PTYManager, orch *agent.Orchestrator) *LocalServer {
	return &LocalServer{
		queueMgr: queueMgr,
		ptyMgr:   ptyMgr,
		orch:     orch,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

func (s *LocalServer) Start(port string) {
	http.HandleFunc("/ws/local", s.handleConnection)
	log.Printf("Local P2P Server starting on :%s", port)
	go func() {
		if err := http.ListenAndServe(":"+port, nil); err != nil {
			log.Printf("Local server error: %v", err)
		}
	}()
}

func (s *LocalServer) handleConnection(w http.ResponseWriter, r *http.Request) {
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Local connection failed:", err)
		return
	}
	defer conn.Close()

	log.Println("⚡️ Local P2P device connected!")

	// Start write pump using channels
	go s.writePump(conn)

	// Read pump
	for {
		var env protocol.Envelope
		if err := conn.ReadJSON(&env); err != nil {
			log.Println("Local P2P connection closed:", err)
			break
		}

		switch env.Type {
		case "local_auth":
			log.Println("✅ Local P2P connection authorized with session:", env.SessionID)
		case "ai_task":
			go s.orch.HandleTask(env.Payload)
		case protocol.TypePTYInput:
			data, err := base64.StdEncoding.DecodeString(env.Payload)
			if err == nil {
				s.ptyMgr.Write(data)
			}
		case protocol.TypePTYResize:
			var size struct {
				Cols int `json:"cols"`
				Rows int `json:"rows"`
			}
			if err := json.Unmarshal([]byte(env.Payload), &size); err == nil {
				s.ptyMgr.Resize(size.Cols, size.Rows)
			}
		case protocol.TypeAIResponse:
			var resp protocol.AIApprovalResponse
			if err := json.Unmarshal([]byte(env.Payload), &resp); err == nil {
				s.queueMgr.ResolveRequest(resp)
			}
		}
	}
}

func (s *LocalServer) writePump(conn *websocket.Conn) {
	ptyStream := s.ptyMgr.Subscribe()
	approvalStream := s.queueMgr.Subscribe()

	for {
		select {
		case data, ok := <-ptyStream:
			if !ok {
				return
			}
			payload := base64.StdEncoding.EncodeToString(data)
			conn.WriteJSON(protocol.Envelope{
				Type:    protocol.TypePTYStream,
				Payload: payload,
			})

		case req, ok := <-approvalStream:
			if !ok {
				return
			}
			b, err := json.Marshal(req)
			if err == nil {
				conn.WriteJSON(protocol.Envelope{
					Type:    protocol.TypeAIRequest,
					Payload: string(b),
				})
			}
		}
	}
}
