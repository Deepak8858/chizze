# ══════════════════════════════════════════
# Chizze — Makefile
# Common build, test, deploy commands
# ══════════════════════════════════════════

.PHONY: help dev test lint build deploy clean docker-build docker-up docker-down \
        go-test go-lint go-build flutter-test flutter-lint flutter-build \
        android-apk android-aab

# ─── Default Target ───
help: ## Show this help
	@echo "Chizze - Available Commands:"
	@echo "════════════════════════════════════════"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─── Development ───
dev: ## Start backend in development mode
	cd backend && go run ./cmd/server

dev-docker: ## Start all services via Docker Compose (dev)
	cd backend && docker compose up --build

# ─── Go Backend ───
go-build: ## Build Go backend binary
	cd backend && CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/chizze-api ./cmd/server

go-test: ## Run Go tests with coverage
	cd backend && go test -v -race -coverprofile=coverage.out ./...
	@cd backend && go tool cover -func=coverage.out | tail -1

go-lint: ## Lint Go code
	cd backend && golangci-lint run --timeout=5m

go-vuln: ## Run Go vulnerability check
	cd backend && govulncheck ./...

go-deps: ## Download Go dependencies
	cd backend && go mod download && go mod tidy

# ─── Flutter ───
flutter-test: ## Run Flutter tests with coverage
	flutter test --coverage

flutter-lint: ## Analyze Flutter code
	flutter analyze --no-fatal-infos

flutter-deps: ## Install Flutter dependencies
	flutter pub get

flutter-build: ## Build Flutter web
	flutter build web --release

# ─── Android ───
android-apk: ## Build release APK (split per ABI)
	flutter build apk --release --split-per-abi

android-aab: ## Build release App Bundle
	flutter build appbundle --release

# ─── Docker ───
docker-build: ## Build Docker images for production
	cd backend && docker build -t chizze-api:latest .

docker-up: ## Start production stack
	cd deploy && docker compose -f docker-compose.prod.yml up -d

docker-down: ## Stop production stack
	cd deploy && docker compose -f docker-compose.prod.yml down

docker-logs: ## Tail production logs
	cd deploy && docker compose -f docker-compose.prod.yml logs -f

# ─── Combined ───
test: go-test flutter-test ## Run all tests

lint: go-lint flutter-lint ## Run all linters

build: go-build flutter-build ## Build everything

# ─── Cleanup ───
clean: ## Remove build artifacts
	rm -rf backend/bin backend/coverage.out
	rm -rf build/app/outputs
	flutter clean

# ─── Deploy ───
deploy-staging: ## Deploy to staging (auto from develop branch)
	@echo "Deploy to staging via CI/CD (push to develop branch)"
	@echo "Run: git push origin develop"

deploy-prod: ## Deploy to production (auto from main branch)
	@echo "Deploy to production via CI/CD (push to main branch)"
	@echo "Run: git push origin main"
