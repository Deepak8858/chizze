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
		stop:        make(chan struct{}),
	}
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
			}
			h.userClients[client.UserID][client] = true
			h.mu.Unlock()
			log.Printf("Client registered: %s", client.UserID)
		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				if uc := h.userClients[client.UserID]; uc != nil {
					delete(uc, client)
					if len(uc) == 0 {
						delete(h.userClients, client.UserID)
					}
				}
				close(client.send)
				log.Printf("Client unregistered: %s", client.UserID)
			}
			h.mu.Unlock()
		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.send <- message:
				default:
					close(client.send)
					delete(h.clients, client)
				}
			}
			h.mu.RUnlock()
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
	h.mu.RLock()
	defer h.mu.RUnlock()
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
			close(client.send)
			delete(h.clients, client)
			delete(h.userClients[userID], client)
			log.Printf("[ws] SendToUser: dropped slow client for user %s", userID)
		}
	}
	log.Printf("[ws] SendToUser: delivered message to %d/%d connections for user %s", sent, len(clients), userID)
}
