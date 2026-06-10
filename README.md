# 🪐 Orbit AI Terminal

Orbit is a state-of-the-art, secure, and AI-powered remote terminal ecosystem. It allows you to access and control your macOS terminal securely from your iPhone anywhere in the world. 

Instead of typing complex Unix commands on a tiny software keyboard, Orbit integrates an autonomous **Groq AI Agent** that reads your screen, listens to natural language prompts, and proposes the exact commands needed to achieve your goal—waiting securely in an inbox for your final approval.

---

## 🏗️ Architecture Overview

The Orbit ecosystem consists of four deeply integrated components:

1. **`orbit-relay` (Global WebSocket Router)**: A lightweight Go server deployed to Railway that brokers WebSocket connections between your Mac and iPhone.
2. **`orbitd` (Mac Background Daemon)**: A headless Go binary that binds to a Unix Pseudo-Terminal (`zsh`), interfaces with the Groq AI API, and communicates securely with the relay.
3. **`OrbitMac` (macOS UI Wrapper)**: A sleek native SwiftUI Menu Bar app that manages the Go daemon, displays connection status, and parses logs.
4. **`Termy` (iOS Client App)**: A rich, native iOS application featuring a real-time `SwiftTerm` emulator and an AI Inbox for approving commands.

---

## ⚙️ Core Components & Technologies

### 1. The Relay Server (`orbit-relay`)
- **Location**: `/orbit-relay`
- **Tech Stack**: Go, `gorilla/websocket`
- **Role**: Because Macs often sit behind NATs and Firewalls, direct connections (like SSH) fail remotely without a VPN. The Relay Server solves this.
- **How it works**: 
  - Exposes two endpoints: `/ws/mac` and `/ws/ios`.
  - Is completely "dumb" and protocol-agnostic. Once a Mac and iOS device are paired, it simply acts as a high-speed pipe, blindly forwarding JSON `Envelope` packets back and forth using a shared `SessionID`.

### 2. The Mac Daemon (`orbitd`)
- **Location**: `/orbitd`
- **Tech Stack**: Go, `creack/pty`, `joho/godotenv`
- **Role**: The brain of the host machine. 
- **PTY Manager**: Uses `creack/pty` to spawn a raw `zsh` session. It reads `stdout/stderr` and broadcasts it to the iOS app, and pipes incoming keystrokes into `stdin`. 
- **AI Agent Orchestrator**: Maintains a rolling 4KB circular buffer of the terminal output. When an `ai_task` arrives from iOS, it bundles the task and the 4KB buffer (so the AI knows the current OS, directory, and errors) and sends it to Groq.
- **Groq Client**: Uses `llama-3.3-70b-versatile` with a strict `json_object` response format constraint to generate a `proposedCommand` and `aiReasoning`.

### 3. The Mac UI Wrapper (`OrbitMac`)
- **Location**: `/OrbitMac`
- **Tech Stack**: Swift, SwiftUI, `Process`
- **Role**: A beautiful `MenuBarExtra` application that lives in your Mac Menu Bar.
- **Lifecycle**: It uses Swift's `Process()` to launch `orbitd-bin` invisibly in the background. It intercepts the Go daemon's `stdout` using a `Pipe()`, parses the text logs to find the dynamic 6-digit `🔑 PAIRING CODE`, and displays it in the UI.

### 4. The iOS Client (`Termy`)
- **Location**: `/Termy`
- **Tech Stack**: Swift, SwiftUI, `SwiftTerm`
- **Role**: The consumer-facing mobile application.
- **Terminal Emulator**: Uses Miguel de Icaza's `SwiftTerm` to render ANSI escape codes and handle native Unix terminal emulation perfectly.
- **Keyboard Avoidance & Resizing**: The app actively tracks keyboard height. When the terminal view resizes on the iPhone, it fires a `pty_resize` payload over WebSockets so the Mac daemon resizes the `zsh` grid size dynamically, ensuring text never overlaps.
- **Inbox UI**: Displays a frosted-glass overlay "Approval Card" when the AI proposes a command, allowing the user to `[Approve]` or `[Deny]`.

---

## 🔒 The Security & Trust Protocol

Orbit uses a rigorous Zero-Trust architecture designed to prevent unauthorized access.

### 1. Six-Digit Handshake
1. The Mac daemon connects to the Relay and receives a random, temporary **6-digit code**.
2. The user types this code into the iOS app.
3. The Relay matches the code, links the two WebSockets, and establishes a `SessionID`. The 6-digit code is immediately destroyed.

### 2. Device Trust Verification
Just because the relay linked the sockets doesn't mean the Mac trusts the iPhone.
1. The iOS app sends an `auth_request` containing its Device Name and a persistent `Device Token` (if it has one).
2. If the token is empty or unknown, the Mac daemon triggers an AppleScript (`osascript`) to pop up a **native macOS Security Alert**, completely locking the terminal connection.
3. The Mac owner clicks "Trust".
4. The Go daemon generates a secure cryptographically random token, registers it in memory, and sends it back to the iPhone in an `auth_response`.
5. The iPhone saves this token to `UserDefaults` for seamless reconnection in the future!

---

## 📡 The JSON Envelope Protocol

Every single byte of data passed between iOS and Mac is wrapped in a strict JSON `Envelope`.

**Schema**:
```json
{
  "type": "pty_stream",
  "session_id": "abc123xy",
  "payload": "Base64OrJsonString",
  "timestamp": 1718000000
}
```

**Types Used**:
- `pty_stream`: Base64 encoded output from Mac to iOS (renders in SwiftTerm).
- `pty_input`: Base64 encoded keystrokes from iOS to Mac.
- `pty_resize`: JSON payload `{"cols": 80, "rows": 24}` to sync terminal window sizes.
- `ai_task`: A natural language string (e.g., "list all files") sent to the Mac AI Agent.
- `ai_request`: Sent from Mac to iOS containing the AI's JSON proposal (`Reasoning`, `Command`).
- `ai_response`: Sent from iOS to Mac containing `approve` or `deny`.
- `auth_request` / `auth_response`: Trust layer handshake.

---

## 🚀 Setup & Execution Instructions

### 1. Environment Variables
You must provide a Groq API key for the AI to function.
Create a `.env` file at `/Users/shreyanshu/Desktop/term/orbitd/.env`:
```env
GROQ_API_KEY=gsk_your_api_key_here
```

### 2. The Relay Server (Railway)
The production relay is hardcoded as `wss://orbit-production-1a51.up.railway.app`. 
If you want to run it locally:
```bash
cd orbit-relay
go run main.go
```
*(If running locally, update `main.go` in `orbitd` and `WebSocketManager.swift` in `Termy` to point to `127.0.0.1:8081`)*.

### 3. The Mac App & Daemon
1. Navigate to the Mac App directory:
   ```bash
   cd OrbitMac
   ```
2. Build the Daemon and the Mac App using the provided bash script:
   ```bash
   ./build.sh
   ```
3. Run the App:
   ```bash
   open build/OrbitMac.app
   ```
4. Look at the top right of your Mac Menu Bar. Click the **Orbit** icon and select **Start Orbit**. Your pairing code will appear.

### 4. The iOS App
1. Open the `Termy/Termy.xcodeproj` workspace in Xcode.
2. Select your iPhone as the build target.
3. Build and Run (`Cmd+R`).
4. Type the 6-digit code from your Mac Menu Bar into the iOS app and tap the Network icon to connect.
5. Your Mac will show an Alert asking if you want to trust your iPhone. Click "Allow".
6. The terminal will appear!

### 5. Using the AI
1. In the iOS app, tap the **"Ask Orbit AI..."** text field at the bottom.
2. Type a command like: `create a new python file that prints hello world`.
3. Hit the send button.
4. An overlay will pop up summarizing the command. Press **Approve** and watch it execute!
