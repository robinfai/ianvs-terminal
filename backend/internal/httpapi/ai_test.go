package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/httpapi"
	"ianvs-terminal/backend/internal/store"
)

func TestAIGatewayQuotaIsolationPersistenceAndProviderRouting(t *testing.T) {
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer server-secret" {
			t.Error("provider must receive server credential")
		}
		if body["model"] == "deepseek-test" && body["max_tokens"] != float64(123) {
			t.Error("DeepSeek output cap missing")
		}
		if body["model"] == "openai-test" && body["max_completion_tokens"] != float64(456) {
			t.Error("OpenAI output cap missing")
		}
		if body["stream"] == true {
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = w.Write([]byte("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":20,\"prompt_tokens_details\":{\"cached_tokens\":40}}}\n\ndata: [DONE]\n\n"))
			return
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"ok"}}],"usage":{"prompt_tokens":100,"completion_tokens":20,"prompt_tokens_details":{"cached_tokens":40}}}`))
	}))
	defer upstream.Close()
	cfg, db, _ := testAPI(t, config.ModeRemote)
	cfg.AIGateway = &config.AIGateway{DefaultModel: "deepseek", DailyRequests: 2, DailyQuotaPoints: 500000, Models: map[string]config.AIModel{
		"deepseek": {Pricing: config.AIPrice{Input: 300, CachedInput: 6, Output: 1200}, Provider: "deepseek", Endpoint: upstream.URL + "/v1", APIKey: "server-secret", Model: "deepseek-test", MaxOutputTokens: 123},
		"openai":   {Pricing: config.AIPrice{Input: 2000, CachedInput: 100, Output: 10000}, Provider: "openai", Endpoint: upstream.URL + "/v1", APIKey: "server-secret", Model: "openai-test", MaxOutputTokens: 456},
	}}
	resources, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	makeHandler := func() http.Handler { return httpapi.New(cfg, auth.New(db, cfg.TokenTTL), resources).Handler() }
	handler := makeHandler()
	one := register(t, handler, "ai-one", "long-password-for-tests", "")
	two := register(t, handler, "ai-two", "long-password-for-tests", "")
	headers := func(token string) map[string]string { return map[string]string{"Authorization": "Bearer " + token} }
	payload := func(alias string, stream bool) map[string]any {
		return map[string]any{"model": alias, "stream": stream, "max_tokens": 999999, "messages": []map[string]string{{"role": "user", "content": "hello"}}}
	}
	if got := request(t, handler, "POST", "/v1/ai/chat/completions", payload("default", false), nil).Code; got != 401 {
		t.Fatalf("unauthenticated status %d", got)
	}
	if got := request(t, handler, "POST", "/v1/ai/chat/completions", payload("unknown", false), headers(one.Token)).Code; got != 400 {
		t.Fatalf("unknown model %d", got)
	}

	// Exercise durable daily quotas independently of burst limits.
	highRate := 100
	cfg.AIGateway.Users = map[string]config.AIUserPolicy{}
	for _, token := range []string{one.Token, two.Token} {
		identity, err := auth.New(db, cfg.TokenTTL).AuthenticateToken(context.Background(), token)
		if err != nil {
			t.Fatal(err)
		}
		cfg.AIGateway.Users[identity.ID] = config.AIUserPolicy{RequestsPerSecond: &highRate, RequestsPerMinute: &highRate}
	}
	catalog := request(t, handler, "GET", "/v1/ai/models", nil, headers(one.Token))
	var modelList struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
		Default string `json:"default_model"`
	}
	if err := json.Unmarshal(catalog.Body.Bytes(), &modelList); err != nil {
		t.Fatal(err)
	}
	if modelList.Default != "deepseek-test" || len(modelList.Data) != 2 {
		t.Fatal("concrete models missing", catalog.Body.String())
	}
	for _, item := range modelList.Data {
		if item.ID != "deepseek-test" && item.ID != "openai-test" {
			t.Fatal("provider alias exposed", item.ID)
		}
	}
	for _, alias := range []string{"default", "openai-test"} {
		r := request(t, handler, "POST", "/v1/ai/chat/completions", payload(alias, true), headers(one.Token))
		if r.Code != 200 || !strings.Contains(r.Body.String(), "[DONE]") {
			t.Fatalf("completion: %d %s", r.Code, r.Body.String())
		}
	}
	handler = makeHandler() // quota survives gateway recreation
	exhausted := request(t, handler, "POST", "/v1/ai/chat/completions", payload("default", false), headers(one.Token))
	if exhausted.Code != 429 || exhausted.Header().Get("Retry-After") == "" {
		t.Fatalf("quota: %d %s", exhausted.Code, exhausted.Body.String())
	}
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := request(t, handler, "POST", "/v1/ai/chat/completions", payload("openai", false), headers(two.Token))
			if r.Code == 200 {
				accepted.Add(1)
			} else if r.Code != 429 {
				t.Errorf("concurrent quota status %d", r.Code)
			}
		}()
	}
	wg.Wait()
	if accepted.Load() != 2 || calls.Load() != 4 {
		t.Fatalf("accepted %d upstream calls %d", accepted.Load(), calls.Load())
	}
	usage := request(t, handler, "GET", "/v1/ai/usage", nil, headers(one.Token))
	var report struct {
		Usage struct {
			Spent    int64 `json:"spent_nano_usd"`
			Reserved int64 `json:"reserved_nano_usd"`
			Input    int64 `json:"input_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(usage.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if report.Usage.Spent != 366240 || report.Usage.Reserved != 0 || report.Usage.Input != 200 {
		t.Fatalf("incorrect settled usage %s", usage.Body.String())
	}
	models := request(t, handler, "GET", "/v1/ai/models", nil, headers(two.Token))
	if models.Code != 200 || strings.Contains(models.Body.String(), "server-secret") {
		t.Fatalf("model catalog %d %s", models.Code, models.Body.String())
	}
}

func TestAIBudgetReservationsRefundsAndMissingUsage(t *testing.T) {
	var mode atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch mode.Load() {
		case 0:
			w.WriteHeader(400)
		case 1:
			_, _ = w.Write([]byte(`{"choices":[]}`))
		default:
			_, _ = w.Write([]byte(`{"usage":{"prompt_tokens":10,"completion_tokens":5,"prompt_cache_hit_tokens":4}}`))
		}
	}))
	defer upstream.Close()
	cfg, db, _ := testAPI(t, config.ModeRemote)
	cfg.AIGateway = &config.AIGateway{DefaultModel: "ds", DailyRequests: 100, DailyQuotaPoints: 1000, Models: map[string]config.AIModel{
		"ds": {Provider: "deepseek", Endpoint: upstream.URL, APIKey: "test", Model: "deepseek-flash", MaxOutputTokens: 123, Pricing: config.AIPrice{Input: 300, CachedInput: 6, Output: 1200}},
	}}
	resources, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	handler := httpapi.New(cfg, auth.New(db, cfg.TokenTTL), resources).Handler()
	user := register(t, handler, "budget-user", "long-password-for-tests", "")
	highRate := 100
	budgetIdentity, err := auth.New(db, cfg.TokenTTL).AuthenticateToken(context.Background(), user.Token)
	if err != nil {
		t.Fatal(err)
	}
	cfg.AIGateway.Users = map[string]config.AIUserPolicy{budgetIdentity.ID: {RequestsPerSecond: &highRate}}
	headers := map[string]string{"Authorization": "Bearer " + user.Token}
	payload := map[string]any{"messages": []map[string]string{{"role": "user", "content": "hello"}}}
	post := func() int { return request(t, handler, "POST", "/v1/ai/chat/completions", payload, headers).Code }
	read := func() map[string]float64 {
		response := request(t, handler, "GET", "/v1/ai/usage", nil, headers)
		var report struct {
			Usage map[string]float64 `json:"usage"`
		}
		if err := json.Unmarshal(response.Body.Bytes(), &report); err != nil {
			t.Fatal(err)
		}
		return report.Usage
	}
	if post() != 502 {
		t.Fatal("expected upstream rejection")
	}
	if u := read(); u["reserved_nano_usd"] != 0 || u["spent_nano_usd"] != 0 {
		t.Fatalf("rejection must refund: %v", u)
	}
	mode.Store(2)
	if post() != 200 {
		t.Fatal("expected success")
	}
	if u := read(); u["spent_nano_usd"] != 7824 || u["reserved_nano_usd"] != 0 {
		t.Fatalf("actual usage settlement: %v", u)
	}
	mode.Store(1)
	if post() != 200 {
		t.Fatal("expected missing usage response")
	}
	if u := read(); u["pending_requests"] != 1 || u["reserved_nano_usd"] <= 0 {
		t.Fatalf("missing usage must retain reservation: %v", u)
	}
	if post() != 429 {
		t.Fatal("reservation must prevent overspending")
	}
	ledger := request(t, handler, "GET", "/v1/ai/requests", nil, headers)
	var records struct {
		Data []struct {
			ID     string         `json:"id"`
			Status string         `json:"status"`
			Price  config.AIPrice `json:"pricing_snapshot"`
		} `json:"data"`
	}
	if err := json.Unmarshal(ledger.Body.Bytes(), &records); err != nil {
		t.Fatal(err)
	}
	if len(records.Data) != 3 || records.Data[0].Status != "pending" || records.Data[1].Status != "settled" || records.Data[2].Status != "refunded" {
		t.Fatalf("ledger outcomes %s", ledger.Body.String())
	}
	page := request(t, handler, "GET", "/v1/ai/requests?before="+records.Data[0].ID, nil, headers)
	var older struct {
		Data []any `json:"data"`
	}
	if err := json.Unmarshal(page.Body.Bytes(), &older); err != nil {
		t.Fatal(err)
	}
	if len(older.Data) != 2 {
		t.Fatalf("incorrect ledger pagination %s", page.Body.String())
	}
	if strings.Contains(ledger.Body.String(), "hello") || strings.Contains(ledger.Body.String(), "api_key") {
		t.Fatal("ledger leaked prompt or credential")
	}
	// A different authenticated user retains their own budget.
	other := register(t, handler, "other-budget-user", "long-password-for-tests", "")
	headers["Authorization"] = "Bearer " + other.Token
	mode.Store(2)
	if post() != 200 {
		t.Fatal("budgets must be isolated")
	}
	isolated := request(t, handler, "GET", "/v1/ai/requests", nil, headers)
	if err := json.Unmarshal(isolated.Body.Bytes(), &records); err != nil {
		t.Fatal(err)
	}
	if len(records.Data) != 1 {
		t.Fatal("ledger is not user isolated")
	}
	identity, err := auth.New(db, cfg.TokenTTL).AuthenticateToken(context.Background(), other.Token)
	if err != nil {
		t.Fatal(err)
	}
	cfg.AIGateway.Users = map[string]config.AIUserPolicy{identity.ID: {AllowedModels: []string{}}}
	if post() != 403 {
		t.Fatal("model allowlist must reject before provider")
	}
	catalog := request(t, handler, "GET", "/v1/ai/models", nil, headers)
	var models struct {
		Data []any `json:"data"`
	}
	json.Unmarshal(catalog.Body.Bytes(), &models)
	if len(models.Data) != 0 {
		t.Fatal("catalog exposes forbidden models")
	}
	cfg.AIGateway.Users[identity.ID] = config.AIUserPolicy{RequestsPerSecond: &highRate, PricingOverrides: map[string]config.AIPrice{"ds": {Version: "customer-v1", Input: 150, CachedInput: 3, Output: 600}}}
	if post() != 200 {
		t.Fatal("scoped price request failed")
	}
	if u := read(); u["spent_nano_usd"] != 11736 {
		t.Fatalf("scoped price not applied: %v", u)
	}
	snapshot := request(t, handler, "GET", "/v1/ai/requests", nil, headers)
	if err := json.Unmarshal(snapshot.Body.Bytes(), &records); err != nil {
		t.Fatal(err)
	}
	if len(records.Data) != 2 || records.Data[0].Price.Input != 150 || records.Data[1].Price.Input != 300 {
		t.Fatalf("price snapshots changed: %s", snapshot.Body.String())
	}

}
