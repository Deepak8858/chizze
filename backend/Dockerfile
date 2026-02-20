# ══════════════════════════════════════════
# Stage 1: Build
# ══════════════════════════════════════════
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /chizze-api ./cmd/server

# ══════════════════════════════════════════
# Stage 2: Runtime (minimal, non-root)
# ══════════════════════════════════════════
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata curl \
    && addgroup -S chizze && adduser -S chizze -G chizze

WORKDIR /app

COPY --from=builder /chizze-api .
RUN chown chizze:chizze /app/chizze-api

USER chizze

EXPOSE 8080

# Container health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["./chizze-api"]
