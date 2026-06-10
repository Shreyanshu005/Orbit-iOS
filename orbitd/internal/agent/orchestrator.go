package agent

import (
	"bytes"
	"fmt"
	"log"
	"regexp"
	"time"

	"github.com/orbit/orbitd/internal/approval"
	"github.com/orbit/orbitd/internal/pty"
	"github.com/orbit/orbitd/pkg/protocol"
)

var ansiRegex = regexp.MustCompile("[\u001B\u009B][[\\]()#;?]*(?:(?:(?:[a-zA-Z\\d]*(?:;[a-zA-Z\\d]*)*)?\u0007)|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PRZcf-ntqry=><~]))")

func stripANSI(str string) string {
	return ansiRegex.ReplaceAllString(str, "")
}

// Orchestrator simulates an LLM agent observing the terminal.
type Orchestrator struct {
	ptyMgr   *pty.PTYManager
	queueMgr *approval.QueueManager
	groq           *GroqClient
	buffer         []byte
	activeTask     string
	waitingForIdle bool
}

func NewOrchestrator(ptyMgr *pty.PTYManager, queueMgr *approval.QueueManager) *Orchestrator {
	return &Orchestrator{
		ptyMgr:   ptyMgr,
		queueMgr: queueMgr,
		groq:     NewGroqClient(),
		buffer:   make([]byte, 0, 8192),
	}
}

// Start spawns a background routine to observe the PTY output.
func (o *Orchestrator) Start(ptyOutput <-chan []byte) {
	const maxBuffer = 10000 // Keep last 10KB of terminal output

	go func() {
		idleTimer := time.NewTimer(1 * time.Second)
		if !idleTimer.Stop() {
			<-idleTimer.C
		}

		for {
			select {
			case data, ok := <-ptyOutput:
				if !ok {
					return // Channel closed
				}

				// Append to buffer
				o.buffer = append(o.buffer, data...)
				if len(o.buffer) > maxBuffer {
					o.buffer = o.buffer[len(o.buffer)-maxBuffer:]
				}

				// Reset idle timer
				idleTimer.Reset(1000 * time.Millisecond)

				// Check for one-shot trigger phrase (legacy)
				if bytes.Contains(bytes.ToLower(data), []byte("orbit trigger ai")) {
					log.Println("Agent: Detected legacy trigger phrase.")
					// Legacy trigger logic could go here, omitting for brevity.
				}

			case <-idleTimer.C:
				// Terminal is idle
				if o.waitingForIdle && o.activeTask != "" {
					o.waitingForIdle = false
					log.Println("Agent: Terminal is idle. Triggering next step in autonomous loop...")
					go o.stepAgentLoop()
				}
			}
		}
	}()
}

// HandleTask fulfills an explicit natural language task from the user.
func (o *Orchestrator) HandleTask(task string) {
	log.Printf("Agent: Starting new autonomous task: %s", task)
	o.activeTask = task
	o.waitingForIdle = false
	
	// Kick off the first step immediately
	go o.stepAgentLoop()
}

func (o *Orchestrator) stepAgentLoop() {
	if o.activeTask == "" {
		return
	}

	contextStr := stripANSI(string(o.buffer))
	aiResp, err := o.groq.AskWithTask(o.activeTask, contextStr)
	if err != nil {
		log.Printf("Agent: Groq Task API failed: %v", err)
		o.ptyMgr.Write([]byte(fmt.Sprintf("\r\n\033[31m[Orbit AI Task Error] %v\033[0m\r\n", err)))
		o.activeTask = "" // Abort loop
		return
	}

	// Check if the AI considers the goal complete
	if aiResp.IsComplete {
		log.Println("Agent: AI reports task is complete.")
		o.ptyMgr.Write([]byte(fmt.Sprintf("\r\n\033[32m[Orbit AI] Goal Achieved: %s\033[0m\r\n", aiResp.Reasoning)))
		o.activeTask = ""
		return
	}

	req := &protocol.AIApprovalRequest{
		ID:              fmt.Sprintf("req_%d", time.Now().UnixNano()), // Nano to avoid collisions in fast loops
		AIReasoning:     aiResp.Reasoning,
		ProposedCommand: aiResp.ProposedCommand,
		CWD:             "Terminal Context",
		Timestamp:       time.Now(),
		Status:          "pending",
	}

	log.Println("Agent: Sending next proposed command in loop to iOS App...")
	decisionChan := o.queueMgr.AddRequest(req)

	isApproved := <-decisionChan
	if isApproved {
		log.Println("Agent: Loop request approved. Executing and waiting for idle...")
		
		marker := []byte(fmt.Sprintf("\r\n[SYSTEM: EXECUTING '%s']\r\n", req.ProposedCommand))
		o.buffer = append(o.buffer, marker...)
		
		o.ptyMgr.Write([]byte(req.ProposedCommand + "\r\n"))
		
		// Delay enabling idle detection to ensure the PTY starts echoing the command first.
		// This guarantees the Start() loop receives data and cleanly resets the idleTimer.
		go func() {
			time.Sleep(500 * time.Millisecond)
			o.waitingForIdle = true
		}()
	} else {
		log.Println("Agent: Loop request denied. Aborting task loop.")
		o.activeTask = "" // Abort loop
	}
}
