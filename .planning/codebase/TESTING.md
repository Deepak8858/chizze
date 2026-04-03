# Testing Patterns

**Analysis Date:** 2026-04-03

## Test Framework

**Runner:**
- Backend: Go `testing` package via `go test` (see `make go-test` in `Makefile`).
- Flutter: `flutter_test` via `flutter test --coverage` (see `make flutter-test` in `Makefile`).
- Admin web: Not detected. No `test` script is present in `admin/package.json`, and no first-party `*.test.*` or `*.spec.*` files are present under `admin/`.

**Assertion Library:**
- Backend: standard library assertions through `testing.T` (`t.Fatalf`, `t.Errorf`) in files like `backend/internal/handlers/order_handler_test.go`.
- Flutter: `package:flutter_test/flutter_test.dart` matchers (`expect`, `isTrue`, `closeTo`) in files like `test/models/api_response_test.dart` and `test/providers/cart_provider_test.dart`.

**Run Commands:**
```bash
make go-test           # Run backend tests with race detector + coverage.out
make flutter-test      # Run Flutter tests with coverage
make test              # Run both backend + Flutter suites
cd backend && go tool cover -func=coverage.out | tail -1   # Summarize Go coverage
flutter test --coverage                                  # Generate Flutter coverage/lcov.info
```

## Test File Organization

**Location:**
- Backend tests are co-located with source packages:
  - `backend/internal/**/*_test.go`
  - `backend/pkg/**/*_test.go`
- Flutter tests are in a dedicated top-level `test/` tree grouped by concern:
  - `test/models/*_test.dart`
  - `test/providers/*_test.dart`
- Admin web tests: Not present in first-party code.

**Naming:**
- Go: `*_test.go`.
- Flutter: `*_test.dart`.

**Structure:**
```
backend/internal/handlers/order_handler_test.go
backend/internal/testutil/test_env.go
backend/internal/testutil/fake_appwrite.go
backend/internal/services/order_service_test.go
backend/pkg/utils/validators_test.go
test/models/api_response_test.dart
test/providers/cart_provider_test.dart
```

## Test Structure

**Suite Organization:**
```go
func TestPlaceOrder_Success(t *testing.T) {
    te := testutil.NewTestEnv(t)
    defer te.Close()
    seedOrderData(te)

    rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")
    if rec.Code != 201 {
        t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
    }

    resp := te.ParseResponse(rec)
    data, _ := resp["data"].(map[string]interface{})
    if data["status"] != "placed" {
        t.Errorf("expected status=placed, got %v", data["status"])
    }
}
```

```dart
group('ApiResponse.fromJson', () {
  test('successful response with data', () {
    final resp = ApiResponse<String>.fromJson(
      {'success': true, 'data': 'hello', 'error': null, 'meta': null},
      (d) => d as String,
    );
    expect(resp.success, isTrue);
    expect(resp.data, 'hello');
  });
});
```

**Patterns:**
- Backend tests are route-level and behavior-focused, executed through a real gin router configured in `backend/internal/testutil/test_env.go`.
- Backend uses helper seeding (`SeedUser`, `SeedOrder`, `SeedAddress`) and auth request helpers to simulate realistic role-based flows.
- Flutter tests center on deterministic model parsing and provider state transitions, using local factory helpers instead of widget trees.

## Mocking

**Framework:**
- Backend: custom in-memory fakes instead of third-party mocking frameworks (`backend/internal/testutil/fake_appwrite.go`, miniredis in `backend/internal/testutil/test_env.go`).
- Flutter: no dedicated mocking framework is detected in current tests; tests instantiate models/providers directly.
- Admin web: Not applicable (no automated tests detected).

**Patterns:**
```go
fakeAW := NewFakeAppwrite()
mr, _ := miniredis.Run()
te := testutil.NewTestEnv(t)
```

```dart
MenuItem makeItem(...) => MenuItem(...);
CartItem makeCartItem(...) => CartItem(...);
```

**What to Mock:**
- Backend external integrations (Appwrite, Redis) should be mocked/faked through `testutil` when testing handlers/services.
- Time-dependent and role-dependent behavior should be exercised through request helpers (`AuthRequest`, seeded claims) rather than direct struct mutation.

**What NOT to Mock:**
- Do not mock simple pure calculations or value-object parsing (cart totals, model `fromMap`, enum mapping); existing Flutter tests correctly keep these as direct unit tests.

## Fixtures and Factories

**Test Data:**
```go
func seedOrderData(te *testutil.TestEnv) {
    te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
    te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
    te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)
}
```

```dart
MenuItem makeItem({String id = 'i1', double price = 299}) => MenuItem(...);
CartItem makeCartItem({String itemId = 'i1', int quantity = 1}) => CartItem(...);
```

**Location:**
- Backend reusable test infrastructure: `backend/internal/testutil/test_env.go`, `backend/internal/testutil/fake_appwrite.go`.
- Backend file-local fixture helpers: top of test files (for example `seedOrderData` in `backend/internal/handlers/order_handler_test.go`).
- Flutter file-local helper factories: top of provider/model tests (for example in `test/providers/cart_provider_test.dart`).

## Coverage

**Requirements:**
- No explicit minimum coverage threshold is enforced in checked-in configs.
- Coverage generation is present for backend and Flutter in `Makefile`, but gating thresholds are not detected.

**View Coverage:**
```bash
cd backend && go test -v -race -coverprofile=coverage.out ./...
cd backend && go tool cover -func=coverage.out
flutter test --coverage
```

## Test Types

**Unit Tests:**
- Flutter: model parsing, computed getters, and notifier state logic (`test/models/*.dart`, `test/providers/*.dart`).
- Backend: lower-level package tests in `backend/pkg/utils/*_test.go` and service-level tests in `backend/internal/services/*_test.go`.

**Integration Tests:**
- Backend handler tests run full HTTP request/response cycles with middleware and role checks against in-memory fakes (`backend/internal/handlers/order_handler_test.go`, `backend/internal/handlers/delivery_handler_test.go`).

**E2E Tests:**
- Not used in first-party code for admin web, backend, or Flutter.

## Common Patterns

**Async Testing:**
```go
rec := te.AuthRequest("GET", "/api/v1/orders/order_enrich", nil, "cust_enrich", "customer")
if rec.Code != 200 { t.Fatalf("expected 200, got %d", rec.Code) }
```

```dart
test('grandTotal computation', () {
  final state = CartState(items: [makeCartItem(price: 300, quantity: 2)], couponDiscount: 50);
  expect(state.grandTotal, closeTo(585.0, 0.01));
});
```

**Error Testing:**
```go
rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
if rec.Code != 400 { t.Fatalf("expected 400, got %d", rec.Code) }
resp := te.ParseResponse(rec)
if !strings.Contains(resp["error"].(string), "offline") {
    t.Errorf("expected offline error")
}
```

## Critical Coverage Gaps (Admin Order Detail Completeness)

**Admin order detail UI fields (customer name/phone/location):**
- Current UI in `admin/app/(admin)/orders/[id]/page.tsx` displays customer ID and delivery instructions, but does not render customer name, customer phone, delivery address, or customer location coordinates.
- `admin/types/index.ts` `Order` interface does not include `customer_phone`, `delivery_address`, `delivery_latitude`, or `delivery_longitude`, which discourages typed rendering of those fields.
- No first-party admin tests exist to verify order detail rendering (`admin/**/*.{test,spec}.{ts,tsx,js,jsx}`: none detected).

**Backend admin order payload verification:**
- Admin order endpoints in `backend/internal/handlers/admin_handler.go` (`ListOrders`, `GetOrder`) have no dedicated test file (no `*admin*_test.go` under `backend/internal/handlers/`).
- Existing backend order tests validate non-admin `/orders/:id` enrichment for `customer_name` (`TestGetOrder_EnrichesCustomerName` in `backend/internal/handlers/order_handler_test.go`) but do not validate admin `/admin/orders/:id` payload completeness.
- No detected backend tests assert admin payload includes customer phone or location/address fields.

**Risk:**
- The requested admin detail completeness (customer name/phone/location) is currently unverified by automated tests and partially unsupported by typed frontend models.
- Regressions in backend order payload shape or admin rendering can ship unnoticed.

**Priority:** High

---

*Testing analysis: 2026-04-03*
