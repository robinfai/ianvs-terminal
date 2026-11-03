package httpapi_test

import (
	"context"
	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/httpapi"
	"ianvs-terminal/backend/internal/store"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestAILongUTF8HistoryIsNotAModelContextError(t *testing.T) {
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		_, _ = w.Write([]byte(`{"choices":[],"usage":{"prompt_tokens":30000,"completion_tokens":10}}`))
	}))
	defer upstream.Close()
	cfg, db, _ := testAPI(t, config.ModeRemote)
	cfg.AIGateway = &config.AIGateway{DefaultModel: "ds", DailyRequests: 100, DailyQuotaPoints: 500000, Models: map[string]config.AIModel{"ds": {Provider: "deepseek", Endpoint: upstream.URL, APIKey: "test", Model: "deepseek-flash", MaxOutputTokens: 4096, Pricing: config.AIPrice{Input: 300, Output: 1200}}}}
	resources, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	handler := httpapi.New(cfg, auth.New(db, cfg.TokenTTL), resources).Handler()
	user := register(t, handler, "long-history", "long-password-for-tests", "")
	headers := map[string]string{"Authorization": "Bearer " + user.Token}
	// 144 KB UTF-8, well within the client's history allowance, previously
	// rejected as model context overflow even though no upstream call was made.
	payload := map[string]any{"messages": []map[string]string{{"role": "user", "content": strings.Repeat("终端输出", 12000)}}}
	response := request(t, handler, "POST", "/v1/ai/chat/completions", payload, headers)
	if response.Code != 200 || calls.Load() != 1 {
		t.Fatalf("long history rejected: %d %s", response.Code, response.Body.String())
	}
	payload["messages"] = []map[string]string{{"role": "user", "content": strings.Repeat("x", (1<<20)+1)}}
	response = request(t, handler, "POST", "/v1/ai/chat/completions", payload, headers)
	if response.Code != 413 || !strings.Contains(response.Body.String(), "ai_request_too_large") || calls.Load() != 1 {
		t.Fatalf("byte limit lost or mislabeled: %d %s", response.Code, response.Body.String())
	}
	// Distinct token rate policy still applies to large requests.
	identity, err := auth.New(db, cfg.TokenTTL).AuthenticateToken(context.Background(), user.Token)
	if err != nil {
		t.Fatal(err)
	}
	low := 100000
	cfg.AIGateway.Users = map[string]config.AIUserPolicy{identity.ID: {TokensPerMinute: &low}}
	payload["messages"] = []map[string]string{{"role": "user", "content": strings.Repeat("终端输出", 12000)}}
	response = request(t, handler, "POST", "/v1/ai/chat/completions", payload, headers)
	if response.Code != 429 || !strings.Contains(response.Body.String(), "ai_rate_limited") || calls.Load() != 1 {
		t.Fatalf("token policy bypassed: %d %s", response.Code, response.Body.String())
	}
}
