package approval

import (
	"errors"
	"sync"
	"time"

	"github.com/orbit/orbitd/pkg/protocol"
)

// QueueManager handles pending AI approval requests.
type QueueManager struct {
	mu       sync.Mutex
	requests    map[string]*protocol.AIApprovalRequest
	// Channels to notify the executor when an approval response comes in.
	listeners   map[string]chan bool
	subscribers []chan *protocol.AIApprovalRequest
}

func NewQueueManager() *QueueManager {
	return &QueueManager{
		requests:  make(map[string]*protocol.AIApprovalRequest),
		listeners: make(map[string]chan bool),
	}
}

// Subscribe returns a channel that emits new AIApprovalRequests as they are added.
func (qm *QueueManager) Subscribe() <-chan *protocol.AIApprovalRequest {
	qm.mu.Lock()
	defer qm.mu.Unlock()
	ch := make(chan *protocol.AIApprovalRequest, 10)
	qm.subscribers = append(qm.subscribers, ch)
	return ch
}

// AddRequest adds a new request to the queue and returns a channel that will receive the user's decision.
func (qm *QueueManager) AddRequest(req *protocol.AIApprovalRequest) chan bool {
	qm.mu.Lock()
	defer qm.mu.Unlock()

	req.Status = "pending"
	req.Timestamp = time.Now()
	qm.requests[req.ID] = req

	decisionChan := make(chan bool, 1)
	qm.listeners[req.ID] = decisionChan

	// Broadcast to all active WebSocket connections
	for _, sub := range qm.subscribers {
		select {
		case sub <- req:
		default:
		}
	}

	return decisionChan
}

// ResolveRequest processes an incoming response from the iOS client.
func (qm *QueueManager) ResolveRequest(resp protocol.AIApprovalResponse) error {
	qm.mu.Lock()
	defer qm.mu.Unlock()

	req, exists := qm.requests[resp.RequestID]
	if !exists {
		return errors.New("request not found or already resolved")
	}

	listener, hasListener := qm.listeners[resp.RequestID]
	if !hasListener {
		return errors.New("listener not found")
	}

	isApproved := resp.Action == "approve"
	if isApproved {
		req.Status = "approved"
	} else {
		req.Status = "denied"
	}

	// Notify the executor block
	listener <- isApproved
	close(listener)

	// Clean up
	delete(qm.requests, resp.RequestID)
	delete(qm.listeners, resp.RequestID)

	return nil
}

// GetPendingRequests returns a list of all currently pending requests (useful for initial client sync).
func (qm *QueueManager) GetPendingRequests() []protocol.AIApprovalRequest {
	qm.mu.Lock()
	defer qm.mu.Unlock()

	var pending []protocol.AIApprovalRequest
	for _, req := range qm.requests {
		pending = append(pending, *req)
	}
	return pending
}
