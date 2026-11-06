package httpapi

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"gorm.io/gorm"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

func purchaseTestAPI(t *testing.T) (*API, *gorm.DB) {
	t.Helper()
	cfg := config.Config{DatabaseDriver: "sqlite", DatabaseDSN: filepath.Join(t.TempDir(), "purchase.db"), AIGateway: &config.AIGateway{DailyQuotaPoints: 1, ApplePurchases: &config.ApplePurchases{BundleID: "work.ianvs.trail", Environment: "Production", Products: map[string]int64{"credits.test": 10}}}}
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatal(err)
	}
	sql, _ := db.DB()
	t.Cleanup(func() { sql.Close() })
	st, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	return &API{cfg: cfg, store: st, purchaseLimiter: newAnonymousAuthRateLimiter()}, db
}
func purchaseTransaction(api *API, user, id string) appleTransaction {
	p := api.purchasesConfig()
	return appleTransaction{ID: id, BundleID: p.BundleID, ProductID: "credits.test", AccountToken: appleAccountToken(user, p.BundleID), Environment: p.Environment, Type: "Consumable", Quantity: 1, PurchaseDate: time.Now().UnixMilli()}
}
func TestAIPurchaseCreditReplayOwnershipRefund(t *testing.T) {
	api, _ := purchaseTestAPI(t)
	ctx := context.Background()
	tr := purchaseTransaction(api, "one", "123")
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := api.creditApplePurchase(ctx, "one", tr); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	wallet, _ := api.readAIWallet(ctx, "one")
	if wallet.Balance != 20000 {
		t.Fatalf("duplicate credit: %+v", wallet)
	}
	if _, err := api.creditApplePurchase(ctx, "two", tr); !errors.Is(err, errPurchaseOwner) {
		t.Fatalf("cross-account accepted %v", err)
	}
	// The existing purchase retains its original granted amount after config edits.
	api.cfg.AIGateway.ApplePurchases.Products[tr.ProductID] = 99
	if _, err := api.creditApplePurchase(ctx, "one", tr); err != nil {
		t.Fatal(err)
	}
	wallet, _ = api.readAIWallet(ctx, "one")
	if wallet.Balance != 20000 {
		t.Fatal("replay changed amount")
	}
	tr.RevocationDate = time.Now().UnixMilli()
	for i := 0; i < 2; i++ {
		result, err := api.creditApplePurchase(ctx, "one", tr)
		if err != nil || result.Status != "revoked" {
			t.Fatalf("refund %v %+v", err, result)
		}
	}
	wallet, _ = api.readAIWallet(ctx, "one")
	if wallet.Balance != 0 {
		t.Fatalf("duplicate refund %+v", wallet)
	}
	tr.RevocationDate = 0
	if _, err := api.creditApplePurchase(ctx, "one", tr); err != nil {
		t.Fatal(err)
	}
	wallet, _ = api.readAIWallet(ctx, "one")
	if wallet.Balance != 0 {
		t.Fatal("stale transaction restored refund")
	}
}
func TestAIPurchaseRejectInvalidEvidence(t *testing.T) {
	api, _ := purchaseTestAPI(t)
	tests := map[string]func(*appleTransaction){
		"sandbox":      func(v *appleTransaction) { v.Environment = "Sandbox" },
		"bundle":       func(v *appleTransaction) { v.BundleID = "another.app" },
		"product":      func(v *appleTransaction) { v.ProductID = "unknown" },
		"subscription": func(v *appleTransaction) { v.Type = "Auto-Renewable Subscription" },
		"quantity":     func(v *appleTransaction) { v.Quantity = 2 },
		"revoked":      func(v *appleTransaction) { v.RevocationDate = 123 },
		"future":       func(v *appleTransaction) { v.PurchaseDate = time.Now().Add(time.Hour).UnixMilli() },
		"id":           func(v *appleTransaction) { v.ID = "../123" },
		"account":      func(v *appleTransaction) { v.AccountToken = "" },
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			v := purchaseTransaction(api, "one", "124")
			mutate(&v)
			if _, err := api.creditApplePurchase(context.Background(), "one", v); err == nil {
				t.Fatal("invalid purchase credited")
			}
		})
	}
}
func TestAIPurchasedBalanceReserveSettleAndDailyReset(t *testing.T) {
	api, db := purchaseTestAPI(t)
	ctx := context.Background()
	if _, err := api.creditApplePurchase(ctx, "one", purchaseTransaction(api, "one", "123")); err != nil {
		t.Fatal(err)
	}
	entry, err := api.reserveAISpend(ctx, "one", "ds", config.AIModel{}, 5000)
	if err != nil {
		t.Fatal(err)
	}
	if entry.PaidReserved != 3000 {
		t.Fatalf("free not first: %+v", entry)
	}
	if err = api.settleAISpend(ctx, "one", entry.ID, aiAccount{Spent: 2500}, "settled"); err != nil {
		t.Fatal(err)
	}
	wallet, _ := api.readAIWallet(ctx, "one")
	if wallet.Balance != 19500 || wallet.Reserved != 0 {
		t.Fatalf("incorrect settlement %+v", wallet)
	}
	entry, err = api.reserveAISpend(ctx, "one", "ds", config.AIModel{}, 19000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = api.reserveAISpend(ctx, "one", "ds", config.AIModel{}, 501); !errors.Is(err, errAIBudget) {
		t.Fatalf("overspend %v", err)
	}
	if err = api.settleAISpend(ctx, "one", entry.ID, aiAccount{}, "refunded"); err != nil {
		t.Fatal(err)
	}
	wallet, _ = api.readAIWallet(ctx, "one")
	if wallet.Balance != 19500 || wallet.Reserved != 0 {
		t.Fatal(wallet)
	}
	// Move today's account to yesterday as the UTC key would on a new day.
	if err = db.Model(&model.Setting{}).Where("`key` = ?", aiAccountKey("one")).Update("key", "ai.budget.yesterday.one").Error; err != nil {
		t.Fatal(err)
	}
	entry, err = api.reserveAISpend(ctx, "one", "ds", config.AIModel{}, 2000)
	if err != nil || entry.PaidReserved != 0 {
		t.Fatalf("daily reset %+v %v", entry, err)
	}
	wallet, _ = api.readAIWallet(ctx, "one")
	if wallet.Balance != 19500 {
		t.Fatal("purchase balance reset")
	}
	if _, err = api.reserveAISpend(ctx, "two", "ds", config.AIModel{}, 2001); !errors.Is(err, errAIBudget) {
		t.Fatal("cross-user balance used")
	}
}
func TestAIPurchaseHistoryIsolationAndUsageTotals(t *testing.T) {
	api, _ := purchaseTestAPI(t)
	ctx := context.Background()
	for i, user := range []string{"one", "two"} {
		id := []string{"123", "456"}[i]
		if _, err := api.creditApplePurchase(ctx, user, purchaseTransaction(api, user, id)); err != nil {
			t.Fatal(err)
		}
	}
	w := httptest.NewRecorder()
	api.aiPurchases(w, httptest.NewRequest("GET", "/", nil), model.User{ID: "one"}, "")
	if w.Code != 200 {
		t.Fatalf("purchase history status %d: %s", w.Code, w.Body.String())
	}
	var history struct {
		Data []struct {
			TransactionID string `json:"transaction_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &history); err != nil {
		t.Fatal(err)
	}
	// Compare transaction IDs, not arbitrary substrings in timestamps: a
	// valid created_at can contain the other user's numeric transaction ID.
	if len(history.Data) != 1 || history.Data[0].TransactionID != "123" {
		t.Fatalf("unexpected purchase history: %s", w.Body.String())
	}
	w = httptest.NewRecorder()
	api.aiUsage(w, httptest.NewRequest("GET", "/", nil), model.User{ID: "one"}, "")
	var data map[string]any
	json.Unmarshal(w.Body.Bytes(), &data)
	if data["remaining_nano_usd"] != float64(22000) || data["purchased_remaining_nano_usd"] != float64(20000) || data["daily_remaining_nano_usd"] != float64(2000) {
		t.Fatal(data)
	}
}

type purchaseTransport func(*http.Request) (*http.Response, error)

func (f purchaseTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestAppleServerLookupAuthenticatesFixedEndpoint(t *testing.T) {
	api, _ := purchaseTestAPI(t)
	p := api.purchasesConfig()
	p.IssuerID = "issuer"
	p.KeyID = "key"
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	raw, _ := x509.MarshalPKCS8PrivateKey(key)
	p.PrivateKeyFile = filepath.Join(t.TempDir(), "AuthKey.p8")
	os.WriteFile(p.PrivateKeyFile, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: raw}), 0600)
	old := applePurchaseHTTPClient
	t.Cleanup(func() { applePurchaseHTTPClient = old })
	tr := purchaseTransaction(api, "one", "123")
	applePurchaseHTTPClient = &http.Client{Transport: purchaseTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.String() != "https://api.storekit.apple.com/inApps/v1/transactions/123" {
			t.Fatal(r.URL)
		}
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		parts := strings.Split(token, ".")
		if len(parts) != 3 {
			t.Fatal("missing JWT")
		}
		hash := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
		sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
		if len(sig) != 64 || !ecdsa.Verify(&key.PublicKey, hash[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
			t.Fatal("invalid server JWT")
		}
		claims, _ := base64.RawURLEncoding.DecodeString(parts[1])
		if !strings.Contains(string(claims), `"aud":"appstoreconnect-v1"`) || !strings.Contains(string(claims), p.BundleID) {
			t.Fatal(string(claims))
		}
		payload, _ := json.Marshal(tr)
		envelope, _ := json.Marshal(map[string]string{"signedTransactionInfo": "header." + base64.RawURLEncoding.EncodeToString(payload) + ".signature"})
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(string(envelope))), Header: make(http.Header)}, nil
	})}
	got, err := fetchAppleTransaction(context.Background(), p, "123")
	if err != nil || got != tr {
		t.Fatalf("%+v %v", got, err)
	}
	tr.ID = "999"
	if _, err = fetchAppleTransaction(context.Background(), p, "123"); err == nil {
		t.Fatal("mismatched Apple transaction accepted")
	}
}

func TestAppleForgedNotificationCannotRevokeCredit(t *testing.T) {
	api, _ := purchaseTestAPI(t)
	ctx := context.Background()
	if _, err := api.creditApplePurchase(ctx, "one", purchaseTransaction(api, "one", "123")); err != nil {
		t.Fatal(err)
	}
	fakeJWS := func(data any) string {
		raw, _ := json.Marshal(data)
		return "forged." + base64.RawURLEncoding.EncodeToString(raw) + ".invalid"
	}
	payload := fakeJWS(map[string]any{"notificationType": "REFUND", "data": map[string]string{"signedTransactionInfo": fakeJWS(map[string]any{"transactionId": "123", "revocationDate": time.Now().UnixMilli()})}})
	body, _ := json.Marshal(map[string]string{"signedPayload": payload})
	req := httptest.NewRequest("POST", "/", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	api.applePurchaseNotification(w, req)
	// The unverified hint cannot mutate balances when Apple verification fails.
	if w.Code != 503 {
		t.Fatal(w.Code, w.Body.String())
	}
	wallet, _ := api.readAIWallet(ctx, "one")
	if wallet.Balance != 20000 {
		t.Fatalf("forged refund changed wallet %+v", wallet)
	}
}
func TestAIPurchasedBalanceConcurrentReservations(t *testing.T) {
	api, _ := purchaseTestAPI(t)
	api.cfg.AIGateway.DailyQuotaPoints = 0
	ctx := context.Background()
	if _, err := api.creditApplePurchase(ctx, "one", purchaseTransaction(api, "one", "123")); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	accepted := 0
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := api.reserveAISpend(ctx, "one", "ds", config.AIModel{}, 5000)
			if err == nil {
				mu.Lock()
				accepted++
				mu.Unlock()
			} else if !errors.Is(err, errAIBudget) {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if accepted != 4 {
		t.Fatalf("accepted %d, expected 4", accepted)
	}
	wallet, _ := api.readAIWallet(ctx, "one")
	if wallet.Reserved != 20000 {
		t.Fatal(wallet)
	}
}
