package websocket

import (
	"log"
	"sync"
)

// IncomingHandler processes a single raw message received from a WebSocket
// client. Implementations are expected to be concurrency-safe; readPump
// serializes calls per-client but different clients run in their own goroutines.
type IncomingHandler func(client *Client, raw []byte)

// Hub maintains the set of active clients and broadcasts messages to the clients.
type Hub struct {
	// Registered clients.
	clients map[*Client]bool

	// Index: userID → set of clients for O(1) targeted sends.
	userClients map[string]map[*Client]bool

	// userRoles stores the role for each connected userID (unique user, not per socket).
	userRoles map[string]string

	// roleCounts tracks unique connected users by role.
	roleCounts map[string]int

	// Inbound messages from the clients.
	broadcast chan []byte

	// Register requests from the clients.
	register chan *Client

	// Unregister requests from clients.
	unregister chan *Client

	// stop signals Run() to exit.
	stop chan struct{}

	// incomingHandler is called by readPump on every client-sent message when set.
	incomingHandler IncomingHandler

	mu sync.RWMutex
}

// SetIncomingHandler registers a callback that receives every message sent by
// connected clients (e.g. for chat message routing). Safe to call once at startup.
func (h *Hub) SetIncomingHandler(fn IncomingHandler) {
	h.mu.Lock()
	h.incomingHandler = fn
	h.mu.Unlock()
}

// handleIncoming dispatches a client-sent message to the registered handler.
// Returns silently when no handler is set.
func (h *Hub) handleIncoming(client *Client, raw []byte) {
	h.mu.RLock()
	fn := h.incomingHandler
	h.mu.RUnlock()
	if fn != nil {
		fn(client, raw)
	}
}

func NewHub() *Hub {
	// Buffer register/unregister/broadcast so a stalled Run loop iteration
	// (e.g. while holding the mutex to fan out to 1000 clients) can't back
	// up the upgrade handshakes and cause connect stampedes at scale.
	return &Hub{
		broadcast:   make(chan []byte, 256),
		register:    make(chan *Client, 128),
		unregister:  make(chan *Client, 128),
		clients:     make(map[*Client]bool),
		userClients: make(map[string]map[*Client]bool),
		userRoles:   make(map[string]string),
		roleCounts:  make(map[string]int),
		stop:        make(chan struct{}),
	}
}

// removeClientLocked removes a client and cleans role presence when the last
// socket for a user disconnects. Caller must hold h.mu.
func (h *Hub) removeClientLocked(client *Client) {
	if _, ok := h.clients[client]; !ok {
		return
	}

	delete(h.clients, client)
	if uc := h.userClients[client.UserID]; uc != nil {
		delete(uc, client)
		if len(uc) == 0 {
			delete(h.userClients, client.UserID)
			role := h.userRoles[client.UserID]
			if role != "" && h.roleCounts[role] > 0 {
				h.roleCounts[role]--
			}
			delete(h.userRoles, client.UserID)
		}
	}

	close(client.send)
	log.Printf("Client unregistered: %s", client.UserID)
}

func (h *Hub) Run() {
	for {
		select {
		case <-h.stop:
			return
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			if h.userClients[client.UserID] == nil {
				h.userClients[client.UserID] = make(map[*Client]bool)
				role := client.Role
				if role == "" {
					role = "unknown"
				}
				h.userRoles[client.UserID] = role
				h.roleCounts[role]++
			}
			h.userClients[client.UserID][client] = true
			h.mu.Unlock()
			log.Printf("Client registered: %s", client.UserID)
		case client := <-h.unregister:
			h.mu.Lock()
			h.removeClientLocked(client)
			h.mu.Unlock()
		case message := <-h.broadcast:
			h.mu.Lock()
			for client := range h.clients {
				select {
				case client.send <- message:
				default:
					h.removeClientLocked(client)
				}
			}
			h.mu.Unlock()
		}
	}
}

// Stop signals the Run loop to exit.
func (h *Hub) Stop() {
	select {
	case <-h.stop:
		// already stopped
	default:
		close(h.stop)
	}
}

// IsConnected returns true if the given userID has at least one active WebSocket connection.
func (h *Hub) IsConnected(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.userClients[userID]) > 0
}

// SendToUser sends a message to a specific user (O(1) lookup via userClients index).
// At 1000-user scale the previous per-send info logs saturated stdout I/O
// on the hub lock, so we now log only the exceptional paths (no connection
// and slow-client drop).
func (h *Hub) SendToUser(userID string, message []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	clients := h.userClients[userID]
	if len(clients) == 0 {
		return
	}
	for client := range clients {
		select {
		case client.send <- message:
		default:
			h.removeClientLocked(client)
			log.Printf("[ws] SendToUser: dropped slow client for user %s", userID)
		}
	}
}

// PresenceSummary returns unique connected user counts and role breakdown.
func (h *Hub) PresenceSummary() (int, map[string]int) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	byRole := make(map[string]int, len(h.roleCounts))
	for role, count := range h.roleCounts {
		byRole[role] = count
	}

	return len(h.userClients), byRole
}
