package websocket

import (
	"log"
	"sync"
)

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

	mu sync.RWMutex
}

func NewHub() *Hub {
	return &Hub{
		broadcast:   make(chan []byte),
		register:    make(chan *Client),
		unregister:  make(chan *Client),
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

// SendToUser sends a message to a specific user (O(1) lookup via userClients index)
func (h *Hub) SendToUser(userID string, message []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	clients := h.userClients[userID]
	if len(clients) == 0 {
		log.Printf("[ws] SendToUser: NO active WebSocket connections for user %s — message dropped", userID)
		return
	}
	sent := 0
	for client := range clients {
		select {
		case client.send <- message:
			sent++
		default:
			h.removeClientLocked(client)
			log.Printf("[ws] SendToUser: dropped slow client for user %s", userID)
		}
	}
	log.Printf("[ws] SendToUser: delivered message to %d/%d connections for user %s", sent, len(clients), userID)
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
