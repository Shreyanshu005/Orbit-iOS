package agent

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
)

// GroqClient handles requests to the Groq API.
type GroqClient struct {
	apiKey string
	model  string
}

func NewGroqClient() *GroqClient {
	return &GroqClient{
		apiKey: os.Getenv("GROQ_API_KEY"),
		model:  "llama-3.3-70b-versatile",
	}
}

type groqRequest struct {
	Model          string          `json:"model"`
	Messages       []groqMessage   `json:"messages"`
	ResponseFormat *responseFormat `json:"response_format,omitempty"`
}

type groqMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type responseFormat struct {
	Type string `json:"type"`
}

type groqResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

// AIResponse matches the expected JSON format from the LLM.
type AIResponse struct {
	Reasoning       string `json:"aiReasoning"`
	ProposedCommand string `json:"proposedCommand"`
	IsComplete      bool   `json:"isComplete"`
}

// Ask analyzes the terminal buffer and returns a proposed command.
func (c *GroqClient) Ask(contextBuffer string) (*AIResponse, error) {
	if c.apiKey == "" {
		return nil, errors.New("GROQ_API_KEY environment variable is missing")
	}

	systemPrompt := `You are Orbit AI, a highly skilled Unix terminal assistant.
The user has encountered an issue or wants to perform a task.
Analyze the provided terminal buffer.
You must respond in strict JSON format matching exactly this schema:
{
  "aiReasoning": "Brief explanation of what happened and why you are proposing this fix.",
  "proposedCommand": "The exact shell command to execute to fix the issue or achieve the goal."
}`

	reqBody := groqRequest{
		Model: c.model,
		Messages: []groqMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: "Terminal Buffer:\n" + contextBuffer},
		},
		ResponseFormat: &responseFormat{Type: "json_object"},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", "https://api.groq.com/openai/v1/chat/completions", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("groq API error: %d - %s", resp.StatusCode, string(bodyBytes))
	}

	var gResp groqResponse
	if err := json.NewDecoder(resp.Body).Decode(&gResp); err != nil {
		return nil, err
	}

	if len(gResp.Choices) == 0 {
		return nil, errors.New("empty response from Groq")
	}

	content := gResp.Choices[0].Message.Content
	var aiResp AIResponse
	if err := json.Unmarshal([]byte(content), &aiResp); err != nil {
		return nil, fmt.Errorf("failed to parse AI JSON response: %v\nRaw Content: %s", err, content)
	}

	return &aiResp, nil
}

// AskWithTask fulfills a specific user request using the terminal context.
func (c *GroqClient) AskWithTask(task string, contextBuffer string) (*AIResponse, error) {
	if c.apiKey == "" {
		return nil, errors.New("GROQ_API_KEY environment variable is missing")
	}

	systemPrompt := fmt.Sprintf(`You are Orbit AI, a highly skilled Unix terminal assistant.
The user wants you to achieve the following goal: "%s".
Use the provided terminal buffer ONLY to understand the current OS, directory, or state context.

CRITICAL RULES:
1. You must work iteratively, proposing ONE single command at a time.
2. If you need to investigate the environment, propose an investigatory command like "ls -la".
3. Pay close attention to the output of your PREVIOUS command in the buffer. If your last command produced NO output (e.g., grep found nothing), or failed with an error, DO NOT repeat the exact same command. Try a different approach (like using 'find ~ -iname "*name*"' instead of 'ls').
4. If the goal is impossible or you are completely stuck, propose a command like "echo 'I could not achieve this'" and set "isComplete" to true.
5. Once you determine the ultimate goal has been fully achieved, set "isComplete" to true.

You must respond in strict JSON format matching exactly this schema:
{
  "aiReasoning": "Brief explanation of what the command does, or why you are finished.",
  "proposedCommand": "The exact shell command to execute next (leave empty if complete).",
  "isComplete": false
}`, task)

	reqBody := groqRequest{
		Model: c.model,
		Messages: []groqMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: "Terminal Context:\n" + contextBuffer},
		},
		ResponseFormat: &responseFormat{Type: "json_object"},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", "https://api.groq.com/openai/v1/chat/completions", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("groq API error: %d - %s", resp.StatusCode, string(bodyBytes))
	}

	var gResp groqResponse
	if err := json.NewDecoder(resp.Body).Decode(&gResp); err != nil {
		return nil, err
	}

	if len(gResp.Choices) == 0 {
		return nil, errors.New("empty response from Groq")
	}

	content := gResp.Choices[0].Message.Content
	var aiResp AIResponse
	if err := json.Unmarshal([]byte(content), &aiResp); err != nil {
		return nil, fmt.Errorf("failed to parse AI JSON response: %v\nRaw Content: %s", err, content)
	}

	return &aiResp, nil
}
