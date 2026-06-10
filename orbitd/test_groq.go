package main

import (
	"fmt"
	"log"

	"github.com/joho/godotenv"
	"github.com/orbit/orbitd/internal/agent"
)

func main() {
	godotenv.Load(".env")
	client := agent.NewGroqClient()
	
	resp, err := client.AskWithTask("list files", "shreyanshu@macbook % ")
	if err != nil {
		log.Fatalf("Error: %v", err)
	}
	fmt.Printf("Success! Command: %s, Reasoning: %s\n", resp.ProposedCommand, resp.Reasoning)
}
