# Chizze — Production Architecture (50K+ Users)

> **Target:** 50,000 concurrent users, 99.95% uptime, <200ms API p95 latency
> **Scale Profile:** ~500K registered users, ~5K orders/hour peak, ~800 active delivery partners
> **Infrastructure:** Appwrite Cloud (managed BaaS) + Self-hosted Go API + Redis

---

## 1. Production Infrastructure — Scaled Architecture

```
                        ┌──────────────────────┐
                        │    Cloudflare CDN     │
                        │  ┌ WAF + DDoS Shield ┐│
                        │  │ Edge Caching       ││
                        │  │ SSL Termination    ││
                        │  └───────────────────┘│
                        └──────────┬───────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                              ▼
          ┌─────────────────┐            ┌─────────────────┐
          │  API Gateway /  │            │  Static Assets  │
          │  Load Balancer  │            │  (Cloudflare    │
          │  (Nginx/Traefik)│            │   Pages)        │
          │  ┌ Rate Limit  ┐│            └─────────────────┘
          │  │ Circuit Break││
          │  │ Health Check ││
          │  └─────────────┘│
          └────────┬────────┘
                   │
     ┌─────────────┼─────────────────────┐
     ▼             ▼                     ▼
┌──────────┐ ┌──────────┐ ┌──────────────────┐
│ Go API   │ │ Go API   │ │ Go API           │
│ Node 1   │ │ Node 2   │ │ Node 3 (Auto)    │
│ (4 CPU,  │ │ (4 CPU,  │ │                  │
│  8GB RAM)│ │  8GB RAM)│ │  Scales 3→10     │
└────┬─────┘ └────┬─────┘ └────┬─────────────┘
     │             │            │
     └──────┬──────┴────────────┘
            │
     ┌──────┴──────────────────────────────────┐
     │         Data Layer (Self-Managed)        │
     │                                          │
     │  ┌────────────────────────────────────┐  │
     │  │ Redis Cluster (3 nodes, 6GB each)  │  │
     │  │ Cache, Sessions, Rate Limiting,    │  │
     │  │ Pub/Sub (WS cross-instance),       │  │
     │  │ Delivery partner geo-index,        │  │
     │  │ Message Queue (Redis Streams)      │  │
     │  └────────────────────────────────────┘  │
     └──────────────────────────────────────────┘
            │
            ▼
     ┌──────────────────────────────────────────┐
     │   ☁️  APPWRITE CLOUD (Fully Managed)     │
     │                                          │
     │  ┌────────────┐  ┌────────────────────┐ │
     │  │ Database   │  │ Authentication     │ │
     │  │ (Collect-  │  │ (Phone OTP,        │ │
     │  │  ions,     │  │  Google, Apple,     │ │
     │  │  Queries,  │  │  Email, JWT)       │ │
     │  │  Indexes)  │  │                    │ │
     │  └────────────┘  └────────────────────┘ │
     │  ┌────────────┐  ┌────────────────────┐ │
     │  │ Storage    │  │ Realtime (WS)      │ │
     │  │ (Images,   │  │ (Order tracking,   │ │
     │  │  Files,    │  │  live updates,     │ │
     │  │  Avatars)  │  │  subscriptions)    │ │
     │  └────────────┘  └────────────────────┘ │
     │  ┌────────────┐  ┌────────────────────┐ │
     │  │ Functions  │  │ Messaging          │ │
     │  │ (Triggers, │  │ (Push Notifs)      │ │
     │  │  Webhooks) │  │                    │ │
     │  └────────────┘  └────────────────────┘ │
     │                                          │
     │  Appwrite manages internally:            │
     │  ✓ Database (MariaDB) — auto-scaled      │
     │  ✓ File Storage — CDN-backed, auto-scaled│
     │  ✓ Backups — automatic daily              │
     │  ✓ SSL certificates — auto-renewed        │
     │  ✓ DDoS protection — built-in             │
     └──────────────────────────────────────────┘
            │
     ┌──────┴──────────────────────────────────┐
     │         Background Workers (Self-hosted) │
     │  ┌────────────┐  ┌────────────────────┐ │
     │  │ Delivery   │  │ Notification       │ │
     │  │ Matcher    │  │ Worker (FCM/SMS)   │ │
     │  │ (2 inst.)  │  │ (2 instances)      │ │
     │  └────────────┘  └────────────────────┘ │
     │  ┌────────────┐  ┌────────────────────┐ │
     │  │ Analytics  │  │ Payout             │ │
     │  │ Aggregator │  │ Processor          │ │
     │  └────────────┘  └────────────────────┘ │
     └──────────────────────────────────────────┘
            │
     ┌──────┴──────────────────────────────────┐
     │     Observability (Managed Services)     │
     │  ┌────────────────────────────────────┐ │
     │  │ Sentry — Error tracking (Go+Flutter)│ │
     │  │ Grafana Cloud — Metrics + Logs     │ │
     │  │ Better Uptime — Status page + ping │ │
     │  └────────────────────────────────────┘ │
     └──────────────────────────────────────────┘
```

### What Appwrite Cloud handles for you (zero management)

| Component | Self-Hosted (Before) | Appwrite Cloud (Now) |
|---|---|---|
| **Database** | MariaDB (you manage replicas, backups, indexes) | ✅ Managed — auto-scaled, daily backups |
| **File Storage** | MinIO S3 (you manage disks, replication) | ✅ Managed — CDN-backed, auto-scaled |
| **Auth** | Appwrite container (you manage) | ✅ Managed — zero config |
| **Realtime** | Appwrite container (you manage WS scaling) | ✅ Managed — auto-scaled |
| **SSL Certs** | Let's Encrypt (you renew) | ✅ Managed — auto-renewed |
| **Backups** | You configure mysqldump + cron | ✅ Managed — automatic daily |
| **Scaling** | You add read replicas, tune configs | ✅ Managed — transparent |

### What you still manage

| Component | Why |
|---|---|
| **Go API** (Docker, 3-10 nodes) | Custom business logic, order matching, payment processing |
| **Redis** (3-node cluster) | Caching, rate limiting, pub/sub for WebSocket scaling, geo-index |
| **Workers** (2-4 instances) | Background jobs: delivery matching, notifications, analytics |
| **Monitoring** | Sentry + Grafana Cloud (managed SaaS, no infra) |

---

## 2. Capacity Planning for 50,000 Users

### 2.1 Traffic Estimates

```
Registered Users:         500,000
Daily Active Users (DAU):  50,000
Peak Concurrent Users:     12,000 — 15,000
Orders per Day:            30,000 — 50,000
Peak Orders per Hour:       5,000
Active Delivery Partners:     800 (peak)
Active Restaurants:          2,000

API Requests:
  - Avg requests/sec:         800
  - Peak requests/sec:       3,000
  - Location updates/sec:      200 (delivery partners, every 5s)

WebSocket Connections:
  - Concurrent WS:          5,000 (tracking users + partners + restaurants)

Database:
  - Read ops/sec:            5,000
  - Write ops/sec:           1,500
  - Storage growth:           50 GB/month (images + data)
```

### 2.2 Server Sizing

| Component | Spec | Instances | Purpose |
|---|---|---|---|
| **Go API** | 4 vCPU, 8GB RAM | 3-10 (auto) | REST API + WebSocket |
| **Redis Cluster** | 2 vCPU, 6GB RAM | 3 (sentinel) | Cache, sessions, rate limit, pub/sub |
| **Workers** | 2 vCPU, 4GB RAM | 2-4 each | Background processing |
| **Load Balancer** | Managed (cloud) | 1 | Nginx/Traefik + health checks |
| **Appwrite Cloud** | Managed | N/A | Auth, DB, Storage, Realtime, Functions |
| **Monitoring** | Managed SaaS | N/A | Sentry + Grafana Cloud |

**Monthly Cost Estimate:**

| Service | Cost |
|---|---|
| Go API + Redis + Workers (Hetzner/DO) | $150–$300/month |
| Appwrite Cloud (Pro plan) | $15/month + usage |
| Sentry (Team plan) | $26/month |
| Grafana Cloud (Free tier) | $0 |
| Cloudflare (Pro) | $25/month |
| **Total** | **~$220–$370/month** |

> **~50% cheaper** than self-hosted because you don't pay for MariaDB, MinIO, or Appwrite servers.

### 2.3 Auto-Scaling Rules

```yaml
# Go API auto-scaling policy
scaling:
  min_replicas: 3
  max_replicas: 10
  metrics:
    - type: cpu
      target_utilization: 70%
    - type: memory
      target_utilization: 75%
    - type: custom
      metric: requests_per_second
      target: 500    # per pod
    - type: custom
      metric: websocket_connections
      target: 2000   # per pod
  scale_up:
    cooldown: 60s
    step: 2          # Add 2 instances at a time
  scale_down:
    cooldown: 300s   # Wait 5 min before scaling down
    step: 1

# Peak hours auto-schedule (predictive)
scheduled_scaling:
  - cron: "0 11 * * *"   # 11 AM lunch rush
    min_replicas: 5
  - cron: "0 19 * * *"   # 7 PM dinner rush
    min_replicas: 7
  - cron: "0 23 * * *"   # 11 PM wind down
    min_replicas: 3
```

---

## 3. Caching Strategy (Critical for 50K users)

### 3.1 Multi-Layer Cache

```
Layer 1: Flutter Client Cache
  ├── HTTP response cache (Dio interceptor, 5 min TTL)
  ├── Image cache (cached_network_image, 100MB LRU)
  ├── Hive/SQLite local DB for offline-first:
  │   ├── User profile & addresses
  │   ├── Recent orders
  │   ├── Favorite restaurants
  │   └── Cart state (persisted across sessions)
  └── Provider cache (Riverpod keepAlive + autoDispose)

Layer 2: CDN / Edge Cache (Cloudflare)
  ├── Static assets: JS, CSS, fonts, Lottie JSON  (365d cache)
  ├── Restaurant images: cover, logo, menu items   (7d cache, purge on update)
  ├── Promo banners                                 (1h cache)
  └── API responses (GET only, Cache-Control headers):
      ├── /restaurants (nearby)    → 60s stale-while-revalidate
      ├── /restaurants/:id/menu   → 300s (5 min)
      └── /categories             → 3600s (1 hour)

Layer 3: Redis Application Cache (Go Backend)
  ├── Hot restaurant data       → Key: "rest:{id}"          TTL: 5 min
  ├── Menu data                 → Key: "menu:{rest_id}"     TTL: 5 min
  ├── Search results            → Key: "search:{hash}"      TTL: 2 min
  ├── User sessions / JWT       → Key: "sess:{user_id}"     TTL: 15 min
  ├── Rate limit counters       → Key: "rl:{ip}:{endpoint}" TTL: 1 min
  ├── Delivery partner geo-idx  → Sorted Set with geo       TTL: none (live)
  ├── Active order state        → Key: "order:{id}:state"   TTL: 2 hours
  ├── Coupon validation cache   → Key: "coupon:{code}"      TTL: 10 min
  └── Analytics aggregates      → Key: "analytics:{rest}:{date}" TTL: 1 hour

Layer 4: Database Query Cache (Appwrite/MariaDB)
  └── MariaDB query cache + connection pooling
```

### 3.2 Cache Invalidation Strategy

```go
// Event-driven invalidation using Redis Pub/Sub
func InvalidateRestaurantCache(restaurantID string) {
    keys := []string{
        fmt.Sprintf("rest:%s", restaurantID),
        fmt.Sprintf("menu:%s", restaurantID),
    }
    redis.Del(ctx, keys...)

    // Purge CDN cache for this restaurant
    cloudflare.PurgeCache([]string{
        fmt.Sprintf("/api/v1/restaurants/%s*", restaurantID),
    })

    // Notify connected clients via WebSocket
    wsHub.Broadcast("restaurant_updated", restaurantID)
}

// Write-through for critical data (orders)
func CreateOrder(order *Order) error {
    // 1. Write to DB
    err := appwrite.CreateDocument("orders", order)
    // 2. Immediately cache active state
    redis.Set(ctx, fmt.Sprintf("order:%s:state", order.ID), order.Status, 2*time.Hour)
    return err
}
```

### 3.3 Cache Hit Ratio Targets

| Cache Layer | Target Hit Rate | Monitoring Metric |
|---|---|---|
| Flutter local | 60-70% | `cache_hit_ratio_client` |
| CDN (Cloudflare) | 85-90% | Cloudflare Analytics |
| Redis (hot data) | 90-95% | `redis_keyspace_hits / (hits + misses)` |
| DB query cache | 70-80% | MariaDB `Qcache_hits` |

---

## 4. Database Optimization

### 4.1 Appwrite Cloud Database (Managed)

```
With Appwrite Cloud, you don't manage database servers.
Appwrite handles scaling, replication, and backups automatically.

What you DO manage:
  - Collection schemas (defined in implementation_plan.md §2.2)
  - Indexes on collections (via Appwrite Console or SDK)
  - Query optimization (use proper indexes, limit fields)

Appwrite Cloud handles:
  ✓ Database scaling and replication
  ✓ Connection pooling
  ✓ Daily automatic backups
  ✓ Point-in-time recovery
  ✓ SSL between services
```

### 4.2 Redis Connection Pooling (Self-Managed)

```go
// Redis connection pool — this is the only DB you manage directly
redisPool := &redis.Options{
    PoolSize:     50,            // Per Go instance
    MinIdleConns: 10,
    PoolTimeout:  5 * time.Second,
    ReadTimeout:  3 * time.Second,
    WriteTimeout: 3 * time.Second,
}
```

### 4.3 Appwrite Indexes (Optimized for Query Patterns)

```
Define these indexes in Appwrite Console or via SDK:

Collection: orders
  - Index: [customer_id, status]          — Customer order history
  - Index: [restaurant_id, placed_at]     — Restaurant dashboard (DESC)
  - Index: [delivery_partner_id, status]  — Partner active delivery
  - Index: [status, placed_at]            — Admin order queue (DESC)
  - Fulltext: [order_number]              — Order search

Collection: restaurants
  - Index: [city, is_online, rating]      — Discovery feed (DESC)
  - Index: [owner_id]                     — Partner's restaurant
  - Fulltext: [name]                      — Restaurant search
  Note: Geo queries handled via bounding box filter on lat/lng fields

Collection: menu_items
  - Index: [restaurant_id, is_available, sort_order]  — Menu loading
  - Index: [restaurant_id, is_bestseller]              — Bestsellers

Collection: delivery_partners
  - Index: [is_online, is_on_delivery]    — Available partners
  Note: Geo matching done via Redis GEOADD/GEOSEARCH (much faster)

Collection: delivery_locations
  - Index: [order_id, timestamp]          — Tracking playback (DESC)
  Note: Use TTL via scheduled Appwrite Function to delete >24h records

Collection: reviews
  - Index: [restaurant_id, food_rating, created_at]  — Reviews page (DESC)
```

### 4.4 Data Archival Strategy

```
Hot Data (Appwrite Cloud — active collections):
  - Orders: last 90 days
  - Delivery locations: last 24 hours
  - Active sessions: current

Archival (via scheduled Appwrite Function — weekly cron):
  1. Query orders older than 90 days → export as JSON to Appwrite Storage
  2. Delete delivery_locations older than 7 days (Appwrite Function)
  3. Mark archived orders with status "archived" (queryable but not in feeds)
  4. Appwrite Cloud handles its own internal backups automatically

Data Retention Policy:
  - Active data in Appwrite: 90 days (orders), 24h (locations), forever (users/restaurants)
  - Archived data in Appwrite Storage: 1 year (JSON exports)
  - Appwrite Cloud automatic backups: managed by Appwrite (daily)
```

---

## 5. Go Backend — Production Hardening

### 5.1 Circuit Breaker Pattern

```go
import "github.com/sony/gobreaker"

// Circuit breaker for Appwrite calls
var appwriteBreaker = gobreaker.NewCircuitBreaker(gobreaker.Settings{
    Name:        "appwrite",
    MaxRequests: 5,                        // Allow 5 requests in half-open state
    Interval:    30 * time.Second,         // Reset counters every 30s
    Timeout:     10 * time.Second,         // Time in open state before half-open
    ReadyToTrip: func(counts gobreaker.Counts) bool {
        failureRatio := float64(counts.TotalFailures) / float64(counts.Requests)
        return counts.Requests >= 10 && failureRatio >= 0.5  // Trip at 50% failure rate
    },
    OnStateChange: func(name string, from, to gobreaker.State) {
        logger.Warn("Circuit breaker state change",
            zap.String("name", name),
            zap.String("from", from.String()),
            zap.String("to", to.String()),
        )
        metrics.CircuitBreakerState.WithLabelValues(name).Set(float64(to))
    },
})

func GetRestaurant(id string) (*Restaurant, error) {
    result, err := appwriteBreaker.Execute(func() (interface{}, error) {
        return appwrite.GetDocument("restaurants", id)
    })
    if err != nil {
        // Fallback to cache
        return getRestaurantFromCache(id)
    }
    return result.(*Restaurant), nil
}
```

### 5.2 Rate Limiting (Per-Endpoint)

```go
import "golang.org/x/time/rate"

var rateLimiters = map[string]*RateLimitConfig{
    // Auth endpoints — strict
    "POST /auth/send-otp":     {Rate: 5, Burst: 5, Per: time.Hour, Key: "phone"},
    "POST /auth/verify-otp":   {Rate: 10, Burst: 10, Per: time.Hour, Key: "phone"},

    // Read endpoints — generous
    "GET /restaurants":         {Rate: 60, Burst: 30, Per: time.Minute, Key: "user_id"},
    "GET /restaurants/nearby":  {Rate: 30, Burst: 15, Per: time.Minute, Key: "user_id"},
    "GET /restaurants/:id/menu":{Rate: 60, Burst: 30, Per: time.Minute, Key: "user_id"},

    // Write endpoints — moderate
    "POST /orders":            {Rate: 10, Burst: 5, Per: time.Minute, Key: "user_id"},
    "PUT /delivery/location":  {Rate: 20, Burst: 10, Per: time.Minute, Key: "user_id"},

    // Search — moderate
    "GET /search":             {Rate: 30, Burst: 15, Per: time.Minute, Key: "user_id"},

    // Global fallback
    "*":                       {Rate: 100, Burst: 50, Per: time.Minute, Key: "ip"},
}

// DDoS protection: block IPs exceeding 1000 req/min globally
var globalRateLimit = rate.NewLimiter(rate.Every(time.Minute/1000), 100)
```

### 5.3 Graceful Shutdown & Health Checks

```go
func main() {
    srv := &http.Server{
        Addr:         ":8080",
        Handler:      router,
        ReadTimeout:  10 * time.Second,
        WriteTimeout: 30 * time.Second,
        IdleTimeout:  120 * time.Second,
    }

    // Health check endpoints
    router.GET("/health", func(c *gin.Context) {
        c.JSON(200, gin.H{"status": "ok", "version": version, "uptime": uptime()})
    })
    router.GET("/health/ready", func(c *gin.Context) {
        // Check all dependencies
        checks := map[string]error{
            "redis":    redis.Ping(ctx).Err(),
            "appwrite": appwrite.Health(),
            "db":       db.Ping(),
        }
        allOk := true
        for _, err := range checks {
            if err != nil { allOk = false }
        }
        if allOk {
            c.JSON(200, gin.H{"ready": true, "checks": checks})
        } else {
            c.JSON(503, gin.H{"ready": false, "checks": checks})
        }
    })

    // Graceful shutdown
    go srv.ListenAndServe()

    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    logger.Info("Shutting down server...")
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    // 1. Stop accepting new connections
    srv.Shutdown(ctx)
    // 2. Drain WebSocket connections (send close frame)
    wsHub.DrainAll(ctx)
    // 3. Finish in-flight requests
    workerPool.Shutdown(ctx)
    // 4. Close DB connections
    db.Close()
    redis.Close()

    logger.Info("Server gracefully stopped")
}
```

### 5.4 Request Tracing (OpenTelemetry)

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/trace"
)

// Every request gets a trace ID propagated through all services
func OrderHandler(c *gin.Context) {
    ctx, span := otel.Tracer("chizze-api").Start(c.Request.Context(), "CreateOrder")
    defer span.End()

    span.SetAttributes(
        attribute.String("user.id", getUserID(c)),
        attribute.String("restaurant.id", req.RestaurantID),
    )

    // Trace propagates to Appwrite, Redis, external services
    order, err := orderService.Create(ctx, req)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
    }
}
```

### 5.5 Idempotency for Critical Operations

```go
// Prevent duplicate orders during network retries
func CreateOrder(c *gin.Context) {
    idempotencyKey := c.GetHeader("Idempotency-Key")  // Client generates UUID
    if idempotencyKey == "" {
        c.JSON(400, gin.H{"error": "Idempotency-Key header required"})
        return
    }

    // Check if this key was already processed
    existing, err := redis.Get(ctx, "idempotent:"+idempotencyKey).Result()
    if err == nil {
        // Return cached response
        c.Data(200, "application/json", []byte(existing))
        return
    }

    // Process the order
    order, err := orderService.Create(ctx, req)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    // Cache the response for 24 hours
    responseJSON, _ := json.Marshal(order)
    redis.Set(ctx, "idempotent:"+idempotencyKey, responseJSON, 24*time.Hour)

    c.JSON(201, order)
}
```

---

## 6. WebSocket Scaling (5K+ Concurrent Connections)

### 6.1 Connection Management

```go
type WSHub struct {
    mu          sync.RWMutex
    clients     map[string]*WSClient      // userID → client
    rooms       map[string]map[string]bool // roomID → set of userIDs
    broadcast   chan WSMessage
    register    chan *WSClient
    unregister  chan *WSClient
    maxClients  int                        // 5000 per instance
}

// Room-based routing for efficient broadcasts
func (h *WSHub) JoinRoom(userID, roomID string) {
    // Rooms: "order:{orderId}", "restaurant:{restId}", "delivery:{partnerId}"
    h.mu.Lock()
    defer h.mu.Unlock()
    if _, ok := h.rooms[roomID]; !ok {
        h.rooms[roomID] = make(map[string]bool)
    }
    h.rooms[roomID][userID] = true
}

// Efficient broadcast to room (only interested clients)
func (h *WSHub) BroadcastToRoom(roomID string, msg WSMessage) {
    h.mu.RLock()
    defer h.mu.RUnlock()
    for userID := range h.rooms[roomID] {
        if client, ok := h.clients[userID]; ok {
            select {
            case client.send <- msg:
            default:
                // Client buffer full, disconnect
                close(client.send)
                delete(h.clients, userID)
            }
        }
    }
}
```

### 6.2 Multi-Instance WS via Redis Pub/Sub

```go
// When Go API runs multiple instances, WS events must cross instance boundaries
func InitCrossInstanceBroadcast(redis *redis.Client) {
    pubsub := redis.Subscribe(ctx, "ws:broadcast")
    go func() {
        for msg := range pubsub.Channel() {
            var wsMsg WSMessage
            json.Unmarshal([]byte(msg.Payload), &wsMsg)
            // Broadcast to local clients only
            wsHub.BroadcastToRoom(wsMsg.Room, wsMsg)
        }
    }()
}

// When any instance needs to broadcast
func PublishWSEvent(room string, event string, data interface{}) {
    msg := WSMessage{Room: room, Event: event, Data: data}
    payload, _ := json.Marshal(msg)
    redis.Publish(ctx, "ws:broadcast", payload)
}
```

### 6.3 Heartbeat & Reconnection

```go
const (
    writeWait      = 10 * time.Second
    pongWait       = 60 * time.Second
    pingPeriod     = 30 * time.Second    // Must be < pongWait
    maxMessageSize = 4096                 // 4KB max per message
)

// Client-side (Flutter) reconnection strategy
// Exponential backoff: 1s → 2s → 4s → 8s → 16s → max 30s
// With jitter: delay * (0.5 + random(0.5))
```

---

## 7. Flutter Client — Production Hardening

### 7.1 Offline-First Architecture

```dart
// Every feature follows this pattern:
class RestaurantRepository {
  final ApiService _api;
  final LocalDatabase _local;   // Hive or Drift (SQLite)
  final ConnectivityService _connectivity;

  Future<List<Restaurant>> getNearby(LatLng location) async {
    // 1. Return cached data immediately
    final cached = await _local.getCachedRestaurants(location);
    if (cached.isNotEmpty) {
      yield cached;  // Show cached UI instantly
    }

    // 2. Fetch fresh data if online
    if (await _connectivity.isOnline) {
      try {
        final fresh = await _api.getNearbyRestaurants(location);
        await _local.cacheRestaurants(location, fresh);
        yield fresh;  // Update UI with fresh data
      } catch (e) {
        if (cached.isEmpty) rethrow;  // Only error if nothing cached
      }
    }
  }
}
```

### 7.2 Image Optimization

```dart
// Aggressive image optimization for mobile networks
CachedNetworkImage(
  imageUrl: restaurant.coverImageUrl,
  // Request resized image from Appwrite
  imageBuilder: (context, provider) => Image(
    image: provider,
    fit: BoxFit.cover,
  ),
  // Appwrite image transformation URL
  // /v1/storage/buckets/{id}/files/{id}/preview?width=400&height=300&quality=75&output=webp
  maxWidthDiskCache: 800,
  maxHeightDiskCache: 600,
  memCacheWidth: 400,        // Memory cache at display size
  memCacheHeight: 300,
  fadeInDuration: Duration(milliseconds: 200),
  placeholder: (_, __) => ShimmerPlaceholder(),
  errorWidget: (_, __, ___) => DefaultFoodImage(),
)

// LRU cache policy
final imageCache = PaintingBinding.instance.imageCache;
imageCache.maximumSize = 200;           // Max 200 images in memory
imageCache.maximumSizeBytes = 100 << 20; // 100MB max
```

### 7.3 Error Handling & Crash Reporting

```dart
// Global error handling
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Sentry for crash reporting
    await SentryFlutter.init(
      (options) {
        options.dsn = 'https://xxx@sentry.io/xxx';
        options.tracesSampleRate = 0.2;    // 20% of transactions traced
        options.profilesSampleRate = 0.1;  // 10% profiled
        options.environment = kReleaseMode ? 'production' : 'debug';
        options.attachScreenshot = true;
        options.sendDefaultPii = false;    // No PII in error reports
      },
    );

    runApp(ProviderScope(child: ChizzeApp()));
  }, (error, stackTrace) {
    Sentry.captureException(error, stackTrace: stackTrace);
    logger.error('Unhandled error', error: error, stackTrace: stackTrace);
  });

  // Flutter framework errors
  FlutterError.onError = (details) {
    Sentry.captureException(details.exception, stackTrace: details.stack);
  };
}
```

### 7.4 Performance Monitoring

```dart
// Track critical user flows
class PerformanceTracker {
  static void trackOrderFlow() {
    final transaction = Sentry.startTransaction('order_flow', 'user.action');

    // Span: Cart → Checkout
    final cartSpan = transaction.startChild('cart_to_checkout');
    // ... user flow
    cartSpan.finish();

    // Span: Payment
    final paymentSpan = transaction.startChild('payment_processing');
    // ...
    paymentSpan.finish();

    transaction.finish();
  }

  // Track widget build times
  static void trackScreenLoad(String screenName, Duration duration) {
    if (duration > Duration(milliseconds: 500)) {
      Sentry.captureMessage(
        'Slow screen render: $screenName (${duration.inMilliseconds}ms)',
        level: SentryLevel.warning,
      );
    }
  }
}
```

### 7.5 App Size Optimization

```yaml
# android/app/build.gradle
android {
    buildTypes {
        release {
            shrinkResources true
            minifyEnabled true
            proguardFiles 'proguard-rules.pro'

            // Split APKs by ABI (reduces download by ~40%)
            ndk { abiFilters 'arm64-v8a', 'armeabi-v7a' }
        }
    }

    bundle {
        language { enableSplit = true }
        density { enableSplit = true }
        abi { enableSplit = true }
    }
}

# Target app sizes:
#   Android APK: < 25MB (arm64)
#   iOS IPA: < 40MB
#   Deferred loading for partner features (reduces initial download)
```

---

## 8. Observability & Monitoring

### 8.1 Prometheus Metrics (Go Backend)

```go
var (
    httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "chizze_http_requests_total",
    }, []string{"method", "endpoint", "status_code"})

    httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name:    "chizze_http_request_duration_seconds",
        Buckets: []float64{.01, .025, .05, .1, .25, .5, 1, 2.5, 5},
    }, []string{"method", "endpoint"})

    activeWSConnections = promauto.NewGauge(prometheus.GaugeOpts{
        Name: "chizze_ws_active_connections",
    })

    ordersProcessed = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "chizze_orders_total",
    }, []string{"status"})  // placed, confirmed, delivered, cancelled

    deliveryMatchDuration = promauto.NewHistogram(prometheus.HistogramOpts{
        Name:    "chizze_delivery_match_duration_seconds",
        Buckets: []float64{1, 5, 10, 30, 60, 120},
    })

    cacheHitRatio = promauto.NewGaugeVec(prometheus.GaugeOpts{
        Name: "chizze_cache_hit_ratio",
    }, []string{"cache_layer"})

    paymentProcessingDuration = promauto.NewHistogram(prometheus.HistogramOpts{
        Name:    "chizze_payment_duration_seconds",
        Buckets: []float64{.5, 1, 2, 5, 10, 30},
    })
)
```

### 8.2 Grafana Dashboards

```
Dashboard 1: Business Overview
  - Orders per minute (line chart)
  - Revenue today vs yesterday (comparison)
  - Active users (gauge)
  - Top restaurants by orders (bar chart)

Dashboard 2: API Performance
  - Request rate (req/sec)
  - Response time (p50, p95, p99)
  - Error rate (4xx, 5xx)
  - Active WebSocket connections
  - Endpoint latency breakdown

Dashboard 3: Infrastructure Health
  - CPU/Memory per service
  - Redis memory, hit ratio, connected clients
  - MariaDB connections, queries/sec, replication lag
  - Disk usage and I/O
  - Network bandwidth

Dashboard 4: Delivery Operations
  - Active delivery partners (map view)
  - Average match time
  - Average delivery time
  - Partner acceptance rate
  - Orders waiting for pickup

Dashboard 5: Error Tracking
  - Error rate by service
  - Top 10 errors
  - Circuit breaker states
  - Failed payment rate
```

### 8.3 Alerting Rules

```yaml
# Prometheus alerting rules
groups:
  - name: chizze_critical
    rules:
      - alert: HighErrorRate
        expr: rate(chizze_http_requests_total{status_code=~"5.."}[5m]) / rate(chizze_http_requests_total[5m]) > 0.05
        for: 2m
        labels: { severity: critical }
        annotations:
          summary: "API error rate above 5%"

      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(chizze_http_request_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "p95 latency exceeding 2 seconds"

      - alert: DeliveryMatchTimeout
        expr: histogram_quantile(0.95, rate(chizze_delivery_match_duration_seconds_bucket[10m])) > 120
        for: 5m
        labels: { severity: critical }
        annotations:
          summary: "Delivery matching taking >2 minutes at p95"

      - alert: RedisDown
        expr: redis_up == 0
        for: 30s
        labels: { severity: critical }

      - alert: AppwriteDown
        expr: probe_success{job="appwrite"} == 0
        for: 1m
        labels: { severity: critical }

      - alert: HighMemoryUsage
        expr: process_resident_memory_bytes / 1e9 > 6  # > 6GB
        for: 5m
        labels: { severity: warning }

      - alert: WebSocketConnectionSurge
        expr: chizze_ws_active_connections > 4000  # per instance
        for: 2m
        labels: { severity: warning }

      - alert: PaymentFailureSpike
        expr: rate(chizze_orders_total{status="payment_failed"}[5m]) > 0.1
        for: 3m
        labels: { severity: critical }
        annotations:
          summary: "Payment failure rate spiking — check Razorpay"

# Alert channels: PagerDuty (critical), Slack #ops (warning), Email (info)
```

---

## 9. Disaster Recovery & Business Continuity

### 9.1 Backup Strategy

```
Database Backups:
  - MariaDB full backup: Daily at 3 AM (mysqldump + gzip)
  - MariaDB incremental: Every 6 hours (binary log shipping)
  - Redis RDB snapshot: Every 15 minutes
  - Redis AOF: Append-only for point-in-time recovery
  - Appwrite data: Daily via Appwrite CLI export

Backup Storage:
  - Primary: Same region S3/MinIO bucket (encrypted AES-256)
  - Secondary: Cross-region S3 (disaster recovery, 24h delay)
  - Retention: 30 daily + 12 monthly + 1 yearly

Recovery Time Objectives:
  - RTO (Recovery Time):  < 30 minutes
  - RPO (Recovery Point): < 15 minutes (max data loss)
```

### 9.2 Failover Plan

```
Scenario 1: Single Go API instance failure
  Action: Load balancer auto-removes, other instances absorb traffic
  Impact: Zero downtime (health check removes in <10s)

Scenario 2: All Go API instances down
  Action: Auto-scaling spins up new instances, Cloudflare serves cached responses
  Recovery: 2-3 minutes
  Impact: Degraged service (cached data only)

Scenario 3: Redis failure
  Action: Sentinel promotes replica, Go API reconnects
  Recovery: 10-30 seconds
  Impact: Brief cache miss spike, rate limiters reset

Scenario 4: MariaDB primary failure
  Action: Manual failover to read replica (promote to primary)
  Recovery: 5-15 minutes
  Impact: Write operations paused, reads continue

Scenario 5: Complete data center outage
  Action: DNS failover to DR region, restore from cross-region backup
  Recovery: 30-60 minutes
  Impact: Full outage during failover

Scenario 6: Appwrite failure
  Action: Go API returns cached data, queues writes for replay
  Recovery: Depends on Appwrite issue
  Impact: New registrations/auth blocked, cached data served
```

### 9.3 Chaos Engineering

```
Monthly chaos drills:
  1. Kill random Go API pod — verify auto-recovery
  2. Simulate Redis failure — verify cache fallback
  3. Inject 500ms latency — verify timeout handling
  4. Simulate payment gateway failure — verify graceful degradation
  5. Network partition between API and DB — verify circuit breaker
  6. Fill disk to 95% — verify alerts and cleanup
```

---

## 10. CI/CD Pipeline

### 10.1 GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yml
name: Chizze CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  # ── Flutter Tests ──
  flutter-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - run: |
          if [ $(lcov --summary coverage/lcov.info 2>&1 | grep 'lines' | awk '{print $2}' | sed 's/%//') -lt 80 ]; then
            echo "Coverage below 80%"; exit 1
          fi

  # ── Go Tests ──
  go-test:
    runs-on: ubuntu-latest
    services:
      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - run: cd backend && go test ./... -race -coverprofile=coverage.out
      - run: cd backend && go vet ./...
      - run: cd backend && golangci-lint run

  # ── Security Scan ──
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd backend && gosec ./...             # Go security scanner
      - run: trivy fs --severity HIGH,CRITICAL .   # Dependency vulnerabilities

  # ── Build & Deploy (main only) ──
  deploy:
    needs: [flutter-test, go-test, security]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      # Build Go API Docker image
      - run: docker build -t chizze-api:${{ github.sha }} ./backend
      - run: docker push registry.chizze.com/api:${{ github.sha }}

      # Blue-green deployment
      - run: |
          # Deploy new version alongside old
          kubectl set image deployment/chizze-api api=registry.chizze.com/api:${{ github.sha }}
          # Wait for rollout
          kubectl rollout status deployment/chizze-api --timeout=300s
          # If failed, auto-rollback
          if [ $? -ne 0 ]; then
            kubectl rollout undo deployment/chizze-api
            exit 1
          fi

      # Build Flutter Web
      - run: flutter build web --release --dart-define=ENV=production
      - run: npx wrangler pages deploy build/web --project-name=chizze

      # Build Flutter Mobile (triggered separately for app store releases)
```

### 10.2 Deployment Strategy

```
Development:   develop branch → staging server (auto-deploy)
Staging:       PR to main → staging + integration tests
Production:    Merge to main → blue-green deploy with canary (5% traffic)

Canary Process:
  1. Deploy new version to 1 pod (5% traffic via Nginx weight)
  2. Monitor error rate and latency for 10 minutes
  3. If healthy: roll forward to all pods
  4. If unhealthy: auto-rollback, alert team

Feature Flags (for future-proofing):
  - Use Appwrite DB collection "feature_flags"
  - Server-side evaluated, cached in Redis
  - Enables gradual rollout: 1% → 10% → 50% → 100%
  - Instant kill-switch for problematic features
```

---

## 11. Future-Proofing Roadmap

### 11.1 Architecture Evolution Path

```
Phase 1 (Current — 50K users):
  Monolithic Go API + Appwrite
  ↓
Phase 2 (100K-250K users):
  Split Go API into 3 services:
    - Order Service (orders, payments, cart)
    - Discovery Service (restaurants, search, menus)
    - Delivery Service (matching, tracking, partner management)
  Shared: Redis, Appwrite
  Communication: gRPC between services, REST for clients
  ↓
Phase 3 (500K+ users):
  Full microservices + event-driven:
    - Add dedicated Search service (Meilisearch/Elasticsearch)
    - Add dedicated Notification service
    - Add dedicated Analytics service (ClickHouse)
    - Event bus (NATS JetStream / Kafka)
    - API Gateway (Kong/Envoy)
  ↓
Phase 4 (1M+ users):
    - Multi-region deployment
    - Database sharding by city
    - Edge computing for delivery matching
    - ML-based recommendation engine
    - GraphQL API layer
```

### 11.2 Feature Expansion Plan

```
Near-term (3-6 months):
  ✦ Grocery delivery (new vertical)
  ✦ Table reservations at partner restaurants
  ✦ In-app wallet with cashback system
  ✦ Multi-language support (Hindi, Tamil, Telugu, etc.)
  ✦ Voice search ("Order biryani from nearby")
  ✦ Dark/light theme toggle

Mid-term (6-12 months):
  ✦ AI-powered recommendations (TensorFlow Lite on-device)
  ✦ AR menu viewer (3D food preview using AR)
  ✦ Social features (share orders, group ordering, food feed)
  ✦ Subscription meals (daily/weekly meal plans)
  ✦ Kitchen cloud / virtual restaurants support
  ✦ Multi-vendor cart (order from multiple restaurants)

Long-term (12-24 months):
  ✦ Drone delivery integration
  ✦ Autonomous delivery vehicle tracking
  ✦ White-label solution for enterprise clients
  ✦ B2B catering and corporate orders
  ✦ International expansion (multi-currency, multi-region)
  ✦ Carbon footprint tracking per order
```

### 11.3 Plugin / Extension Architecture

```go
// Future-proof: Plugin system for payment gateways
type PaymentGateway interface {
    Name() string
    InitiatePayment(amount float64, orderID string) (*PaymentResponse, error)
    VerifyPayment(paymentID string) (*VerificationResult, error)
    RefundPayment(paymentID string, amount float64) error
    HandleWebhook(payload []byte) (*WebhookEvent, error)
}

// Easy to add new gateways without touching core code
var gateways = map[string]PaymentGateway{
    "razorpay": &RazorpayGateway{},
    "stripe":   &StripeGateway{},
    "paytm":    &PaytmGateway{},   // Add later without core changes
}

// Same pattern for:
// - SMS providers (Twilio, MSG91, Gupshup)
// - Maps providers (Google Maps, MapMyIndia, Mapbox)
// - Push notification services (FCM, OneSignal, SNS)
// - Analytics backends (internal, Mixpanel, Amplitude)
// - Search engines (Appwrite fulltext, Meilisearch, Elasticsearch)
```

### 11.4 API Versioning Strategy

```
URL-based versioning:
  /api/v1/...  — Current stable
  /api/v2/...  — Next version (breaking changes)

Rules:
  - v1 supported for minimum 12 months after v2 launch
  - Deprecation headers: Sunset, Deprecation
  - Client forced-update mechanism via app store minimum version
  - Version negotiation via Accept header for minor changes

Mobile App Version Control:
  - Minimum supported version stored in Appwrite
  - App checks on launch → force update screen if below minimum
  - Gradual rollout: version gates per user segment
```

---

## 12. Load Testing Plan

### 12.1 k6 Test Scenarios

```javascript
// k6 load test: simulates 50K user behavior
import http from 'k6/http';
import { sleep, check } from 'k6';
import ws from 'k6/ws';

export const options = {
  scenarios: {
    // Simulate normal traffic ramp-up
    normal_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m',  target: 100  },  // Warm up
        { duration: '10m', target: 500  },  // Normal load
        { duration: '10m', target: 1000 },  // Peak lunch
        { duration: '5m',  target: 500  },  // Cool down
        { duration: '5m',  target: 0    },
      ],
    },
    // Simulate order spike (flash sale)
    order_spike: {
      executor: 'constant-arrival-rate',
      rate: 100,         // 100 orders per second
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 200,
    },
    // Simulate delivery location updates
    location_updates: {
      executor: 'constant-vus',
      vus: 800,          // 800 delivery partners
      duration: '30m',
    },
  },
  thresholds: {
    http_req_duration: ['p(95) < 200', 'p(99) < 500'],  // p95 < 200ms
    http_req_failed:   ['rate < 0.01'],                  // < 1% error rate
    ws_connecting:     ['p(95) < 1000'],                 // WS connect < 1s
  },
};

export default function () {
  // Simulate user browsing → ordering → tracking
  const restaurants = http.get(`${BASE_URL}/restaurants/nearby?lat=12.97&lng=77.59`);
  check(restaurants, { 'restaurants 200': (r) => r.status === 200 });
  sleep(2);

  const menu = http.get(`${BASE_URL}/restaurants/${restId}/menu`);
  check(menu, { 'menu 200': (r) => r.status === 200 });
  sleep(3);

  const order = http.post(`${BASE_URL}/orders`, JSON.stringify(orderPayload));
  check(order, { 'order 201': (r) => r.status === 201 });
  sleep(1);

  // WebSocket tracking
  ws.connect(`${WS_URL}/ws?token=${token}`, function (socket) {
    socket.on('message', (msg) => {
      check(msg, { 'got_tracking': (m) => JSON.parse(m).event === 'delivery_location' });
    });
    socket.setTimeout(() => socket.close(), 60000);
  });
}
```

### 12.2 Performance Targets

| Metric | Target | Alerting Threshold |
|---|---|---|
| API p50 latency | < 50ms | > 100ms |
| API p95 latency | < 200ms | > 500ms |
| API p99 latency | < 500ms | > 2000ms |
| Order creation latency | < 300ms | > 1000ms |
| WS message delivery | < 100ms | > 500ms |
| Error rate | < 0.1% | > 1% |
| Availability | 99.95% | < 99.9% |
| Cache hit ratio | > 85% | < 70% |
| Delivery match time | < 60s avg | > 120s |
| Time to first byte | < 100ms | > 300ms |
| Mobile app cold start | < 3s | > 5s |
| Home screen render | < 1.5s | > 3s |

---

## 13. Compliance & Legal

```
Data Protection:
  ✓ GDPR/IT Act 2000 compliance
  ✓ Right to data export (user profile, orders)
  ✓ Right to deletion (account + all associated data)
  ✓ Cookie consent on web platform
  ✓ Privacy policy and terms of service
  ✓ Data processing agreements with sub-processors

Food Safety:
  ✓ FSSAI license verification for restaurants
  ✓ Hygiene rating display
  ✓ Allergen information on menu items
  ✓ Food safety incident reporting

Financial:
  ✓ PCI DSS compliance via payment gateway (Razorpay)
  ✓ GST invoice generation
  ✓ TDS compliance for partner payouts
  ✓ Audit trail for all financial transactions

Accessibility:
  ✓ WCAG 2.1 AA compliance
  ✓ Screen reader support
  ✓ High contrast mode
  ✓ Keyboard navigation (web)
```
