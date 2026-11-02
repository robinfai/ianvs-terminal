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

func TestAIRequestAndTokenRateLimitsBeforeUpstream(t *testing.T) {
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.Write([]byte(`{"usage":{"prompt_tokens":10,"completion_tokens":5}}`))
	}))
	defer upstream.Close()
	cfg, db, _ := testAPI(t, config.ModeRemote)
	cfg.AIGateway = &config.AIGateway{DefaultModel: "test", DailyRequests: 100, DailyQuotaPoints: 500000, Models: map[string]config.AIModel{"test": {Provider: "deepseek", Endpoint: upstream.URL, APIKey: "test", Model: "test", MaxOutputTokens: 100, Pricing: config.AIPrice{Input: 300, Output: 1200}}}}
	resources, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	handler := httpapi.New(cfg, auth.New(db, cfg.TokenTTL), resources).Handler()
	user := register(t, handler, "rate-user", "long-password-for-tests", "")
	identity, err := auth.New(db, cfg.TokenTTL).AuthenticateToken(context.Background(), user.Token)
	if err != nil {
		t.Fatal(err)
	}
	// Explicit user override keeps the admission test independent of defaults.
	one := 1
	cfg.AIGateway.Users = map[string]config.AIUserPolicy{identity.ID: {RequestsPerSecond: &one}}
	headers := map[string]string{"Authorization": "Bearer " + user.Token}
	body := map[string]any{"messages": []map[string]string{{"role": "user", "content": "hello"}}}
	if r := request(t, handler, "POST", "/v1/ai/chat/completions", body, headers); r.Code != 200 {
		t.Fatal(r.Body.String())
	}
	body["stream"] = true
	if r := request(t, handler, "POST", "/v1/ai/chat/completions", body, headers); r.Code != 429 || !strings.Contains(r.Body.String(), "ai_rate_limited") || r.Header().Get("Retry-After") == "" {
		t.Fatalf("%d %s", r.Code, r.Body.String())
	}
	if calls.Load() != 1 {
		t.Fatal("limited request reached upstream")
	}
	high, low := 100, 1
	cfg.AIGateway.Users = map[string]config.AIUserPolicy{identity.ID: {RequestsPerSecond: &high, TokensPerMinute: &low}}
	if r := request(t, handler, "POST", "/v1/ai/chat/completions", body, headers); r.Code != 429 {
		t.Fatal("token limit bypassed", r.Code)
	}
	if calls.Load() != 1 {
		t.Fatal("token limited request reached upstream")
	}
}
