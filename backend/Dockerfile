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
# Stage 2: Runtime
# ══════════════════════════════════════════
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app

COPY --from=builder /chizze-api .

EXPOSE 8080

ENTRYPOINT ["./chizze-api"]
