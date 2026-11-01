package httpapi_test

import (
	"encoding/json"
	"fmt"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestAIAdminManagementContracts(t *testing.T) {
	cfg, db, initial := testAPI(t, config.ModeRemote)
	adminSession := register(t, initial, "gateway-admin", "admin-contract-password", "")
	userSession := register(t, initial, "gateway-user", "admin-contract-password", "")
	var admin, user model.User
	db.Where("username = ?", "gateway-admin").First(&admin)
	db.Where("username = ?", "gateway-user").First(&user)
	key := filepath.Join(t.TempDir(), "admin.key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	cfg.AIAdmin = &config.AIAdmin{UserIDs: []string{admin.ID}, EncryptionKeyFile: key}
	cfg.AIGateway = &config.AIGateway{DefaultModel: "ds", DailyQuotaPoints: 500000, DailyRequests: 100, Models: map[string]config.AIModel{"ds": {Provider: "deepseek", Endpoint: "https://api.deepseek.com", APIKey: "secret-never-return", Model: "deepseek-chat", MaxOutputTokens: 1024, Pricing: config.AIPrice{Version: "v1", Input: 300, CachedInput: 30, Output: 1200}}}}
	handler := testAPIHandler(t, cfg)
	ah := map[string]string{"Authorization": "Bearer " + adminSession.Token}
	uh := map[string]string{"Authorization": "Bearer " + userSession.Token}
	for _, route := range []string{"/v1/admin/ai/gateway", "/v1/admin/ai/users", "/v1/admin/ai/requests", "/v1/admin/ai/audit"} {
		if res := request(t, handler, http.MethodGet, route, nil, uh); res.Code != 403 {
			t.Fatalf("non-admin allowed %s: %d", route, res.Code)
		}
		if res := request(t, handler, http.MethodGet, route, nil, nil); res.Code != 401 {
			t.Fatalf("anonymous allowed %s: %d", route, res.Code)
		}
	}
	for _, route := range []string{"/v1/admin/ai/gateway", "/v1/admin/ai/users/" + user.ID + "/policy"} {
		if res := request(t, handler, http.MethodPut, route, map[string]any{}, uh); res.Code != 403 {
			t.Fatal("unauthorized mutation")
		}
	}
	get := request(t, handler, http.MethodGet, "/v1/admin/ai/gateway", nil, ah)
	if get.Code != 200 || strings.Contains(get.Body.String(), "secret-never-return") {
		t.Fatal("provider secret exposed")
	}
	var gateway map[string]any
	json.Unmarshal(get.Body.Bytes(), &gateway)
	gateway["daily_quota_points"] = float64(200)
	save := func() int {
		return request(t, handler, http.MethodPut, "/v1/admin/ai/gateway", map[string]any{"gateway": gateway, "reason": "test budget update"}, ah).Code
	}
	if save() != 200 {
		t.Fatal("valid save failed")
	}
	if save() != 409 {
		t.Fatal("stale revision did not conflict")
	}
	var encrypted model.Setting
	db.Where("`key` = ?", "ai.admin.config.v1").First(&encrypted)
	if encrypted.Value == "" || strings.Contains(encrypted.Value, "secret-never-return") || strings.Contains(encrypted.Value, "api.deepseek.com") {
		t.Fatal("configuration not encrypted")
	}
	handler = testAPIHandler(t, cfg)
	res := request(t, handler, http.MethodGet, "/v1/ai/usage", nil, uh)
	if res.Code != 200 || !strings.Contains(res.Body.String(), `"daily_quota_points":200`) {
		t.Fatalf("live/restart config missing: %s", res.Body.String())
	}
	creditPath := "/v1/admin/ai/users/" + user.ID + "/credits"
	adjustment := map[string]any{"operation_id": "12345678-1234-1234-1234-123456789012", "points": 100, "reason": "grant test credits"}
	var wg sync.WaitGroup
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rr := request(t, handler, http.MethodPost, creditPath, adjustment, ah)
			if rr.Code != 200 {
				t.Errorf("credit failed %s", rr.Body.String())
			}
		}()
	}
	wg.Wait()
	var wallet model.Setting
	db.Where("`key` = ?", "ai.wallet."+user.ID).First(&wallet)
	if !strings.Contains(wallet.Value, `"balance_nano_usd":200000`) {
		t.Fatalf("double credit %s", wallet.Value)
	}
	adjustment["points"] = 101
	if request(t, handler, http.MethodPost, creditPath, adjustment, ah).Code != 409 {
		t.Fatal("idempotency mismatch accepted")
	}
	adjustment["operation_id"] = "22345678-1234-1234-1234-123456789012"
	adjustment["points"] = -101
	if request(t, handler, http.MethodPost, creditPath, adjustment, ah).Code != 400 {
		t.Fatal("overdraw allowed")
	}
	var count int64
	db.Model(&model.Setting{}).Where("`key` LIKE ?", "ai.admin.audit.%").Count(&count)
	if count != 2 {
		t.Fatalf("audit count %d", count)
	}
	policy := map[string]any{"revision": 1, "reason": "disable test account", "policy": map[string]any{"disabled": true, "allowed_models": nil}}
	res = request(t, handler, http.MethodPut, "/v1/admin/ai/users/"+user.ID+"/policy", policy, ah)
	if res.Code != 200 {
		t.Fatal(res.Body.String())
	}
	res = request(t, handler, http.MethodGet, "/v1/ai/models", nil, uh)
	if !strings.Contains(res.Body.String(), `"data":[]`) {
		t.Fatal("disabled policy not applied")
	}
	for i := 0; i < 55; i++ {
		id := fmt.Sprintf("%048x", i)
		entry := fmt.Sprintf(`{"id":%q,"model":"ds","provider":"deepseek","status":"settled","usage":{"spent_nano_usd":2000,"input_tokens":10,"cached_input_tokens":2,"output_tokens":3},"created_at":%q}`, id, time.Now().UTC().Format(time.RFC3339Nano))
		if err := db.Create(&model.Setting{Key: "ai.ledger." + user.ID + "." + id, Value: entry}).Error; err != nil {
			t.Fatal(err)
		}
	}
	res = request(t, handler, http.MethodGet, "/v1/admin/ai/requests?user_id="+user.ID+"&status=settled", nil, ah)
	var page struct {
		Data    []any  `json:"data"`
		Next    string `json:"next_cursor"`
		Summary struct {
			Requests int64 `json:"requests"`
			Spent    int64 `json:"spent_nano_usd"`
		} `json:"summary"`
	}
	if json.Unmarshal(res.Body.Bytes(), &page) != nil || res.Code != 200 || len(page.Data) != 50 || page.Next == "" || page.Summary.Requests != 55 || page.Summary.Spent != 110000 {
		t.Fatalf("ledger query wrong: %s", res.Body.String())
	}
	res = request(t, handler, http.MethodGet, "/v1/admin/ai/requests?user_id="+user.ID+"&status=settled&before="+page.Next, nil, ah)
	if json.Unmarshal(res.Body.Bytes(), &page) != nil || len(page.Data) != 5 {
		t.Fatalf("ledger next page wrong: %s", res.Body.String())
	}
	res = request(t, handler, http.MethodGet, "/v1/admin/ai/audit", nil, ah)
	if strings.Contains(res.Body.String(), "secret-never-return") {
		t.Fatal("audit leaked key")
	}
	if err := os.WriteFile(key, []byte(strings.Repeat("x", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	if request(t, handler, http.MethodGet, "/v1/ai/models", nil, uh).Code != 503 {
		t.Fatal("corrupt encryption key did not fail closed")
	}
}
