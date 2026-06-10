package pty

import (
	"io"
	"log"
	"os"
	"os/exec"

	"github.com/creack/pty"
)

// PTYManager encapsulates a spawned shell session.
type PTYManager struct {
	ptmx        *os.File
	cmd         *exec.Cmd
	subscribers []subscriber
}

func NewPTYManager() (*PTYManager, error) {
	// Spawn zsh by default on macOS
	c := exec.Command("zsh", "-l")
	
	// Start the command with a pty.
	ptmx, err := pty.Start(c)
	if err != nil {
		return nil, err
	}

	mgr := &PTYManager{
		ptmx: ptmx,
		cmd:  c,
	}

	// Start reading from PTY and broadcasting
	go mgr.readLoop()

	return mgr, nil
}

type subscriber chan []byte

func (p *PTYManager) Subscribe() <-chan []byte {
	ch := make(chan []byte, 100)
	// In production, we'd use a mutex to append to a list of subscribers.
	// For this MVP, we assume hardcoded 2 subscribers (Agent and WS).
	p.subscribers = append(p.subscribers, ch)
	return ch
}

func (p *PTYManager) readLoop() {
	buf := make([]byte, 1024)
	for {
		n, err := p.ptmx.Read(buf)
		if err != nil {
			if err == io.EOF {
				log.Println("PTY read loop closed (EOF)")
			} else {
				log.Println("PTY read error:", err)
			}
			break
		}

		if n > 0 {
			data := make([]byte, n)
			copy(data, buf[:n])
			
			for _, sub := range p.subscribers {
				select {
				case sub <- data:
				default:
				}
			}
		}
	}
}

// Write allows the WebSocket or Agent to send bytes (keystrokes) to the shell.
func (p *PTYManager) Write(data []byte) (int, error) {
	return p.ptmx.Write(data)
}

// Close gracefully terminates the shell session.
func (p *PTYManager) Close() error {
	for _, sub := range p.subscribers {
		close(sub)
	}
	if p.ptmx != nil {
		p.ptmx.Close()
	}
	if p.cmd != nil && p.cmd.Process != nil {
		p.cmd.Process.Kill()
	}
	return nil
}

// Resize changes the size of the underlying PTY session
func (p *PTYManager) Resize(cols, rows int) error {
	if p.ptmx != nil {
		return pty.Setsize(p.ptmx, &pty.Winsize{
			Rows: uint16(rows),
			Cols: uint16(cols),
		})
	}
	return nil
}
