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

// SendToUser sends a message to a specific user (O(1) lookup via userClients index)
func (h *Hub) SendToUser(userID string, message []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for client := range h.userClients[userID] {
		select {
		case client.send <- message:
		default:
			close(client.send)
			delete(h.clients, client)
			delete(h.userClients[userID], client)
		}
	}
}
