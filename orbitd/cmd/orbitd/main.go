package main

import (
	"log"

	"github.com/joho/godotenv"
	"github.com/orbit/orbitd/internal/agent"
	"github.com/orbit/orbitd/internal/approval"
	"github.com/orbit/orbitd/internal/network"
	"github.com/orbit/orbitd/internal/pty"
)

func main() {
	// Attempt to load .env file from current directory
	godotenv.Load(".env")

	log.Println("orbitd: Starting AI Remote Terminal Daemon...")

	// Initialize the Approval Queue State Machine
	queueMgr := approval.NewQueueManager()

	// Initialize the PTY Manager
	ptyMgr, err := pty.NewPTYManager()
	if err != nil {
		log.Fatalf("orbitd: Failed to start PTY: %v", err)
	}
	defer ptyMgr.Close()

	// Initialize the AI Agent Orchestrator
	orchestrator := agent.NewOrchestrator(ptyMgr, queueMgr)
	
	// Start the Agent observing the PTY
	agentPTYStream := ptyMgr.Subscribe()
	orchestrator.Start(agentPTYStream)

	// Initialize Local P2P Server
	localServer := network.NewLocalServer(queueMgr, ptyMgr, orchestrator)
	localServer.Start("8082")

	// Connect to the Relay Server
	relayClient := network.NewRelayClient(queueMgr, ptyMgr, orchestrator)
	
	// Switch to production relay
	relayURL := "wss://orbit-kdps.onrender.com/ws/mac"
	
	err = relayClient.Connect(relayURL)
	if err != nil {
		log.Fatalf("orbitd: Failed to connect to Relay Server: %v", err)
	}

	// Block forever while daemon runs
	select {}
}
