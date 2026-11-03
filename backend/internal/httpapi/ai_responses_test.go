package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestResponsesPayload(t *testing.T) {
	if !usesAIResponses("openai", "https://api.openai.com/v1") || usesAIResponses("deepseek", "https://api.deepseek.com/v1") || usesAIResponses("openai", "https://example.com/v1") {
		t.Fatal("protocol")
	}
	var chat map[string]json.RawMessage
	_ = json.Unmarshal([]byte(`{"model":"gpt-6.1-sol","messages":[{"role":"system","content":"safe"},{"role":"assistant","tool_calls":[{"id":"c1","type":"function","function":{"name":"read_screen","arguments":"{}"}}]},{"role":"tool","tool_call_id":"c1","content":"done"}],"max_completion_tokens":4096,"stream":true,"tools":[{"type":"function","function":{"name":"read_screen","parameters":{"type":"object"}}}],"tool_choice":"auto","parallel_tool_calls":false}`), &chat)
	out, err := aiResponsesPayload(chat)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(out)
	var d map[string]any
	_ = json.Unmarshal(b, &d)
	if d["store"] != false || d["max_output_tokens"] != float64(4096) || d["parallel_tool_calls"] != false || d["messages"] != nil {
		t.Fatal(string(b))
	}
	input := d["input"].([]any)
	if input[1].(map[string]any)["type"] != "function_call" || input[2].(map[string]any)["call_id"] != "c1" {
		t.Fatal(input)
	}
	tool := d["tools"].([]any)[0].(map[string]any)
	if tool["strict"] != false || tool["name"] != "read_screen" {
		t.Fatal(tool)
	}
}
func TestResponsesStreamSafetyAndAccounting(t *testing.T) {
	const completed = `{"type":"response.completed","response":{"id":"resp_1","model":"gpt-6.1-sol","status":"completed","output":[{"type":"function_call","call_id":"c1","name":"read_screen","arguments":"{}"}],"usage":{"input_tokens":100,"output_tokens":20,"input_tokens_details":{"cached_tokens":40}}}}`
	prefix := "data: {\"type\":\"response.created\"}\n\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n"
	var out bytes.Buffer
	if err := translateAIResponses(strings.NewReader(prefix+"data: "+completed+"\n\n"), true, &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), `"tool_calls"`) || !strings.HasSuffix(out.String(), "data: [DONE]\n\n") || strings.Count(out.String(), "hello") != 1 {
		t.Fatal(out.String())
	}
	paid := false
	for _, line := range strings.Split(out.String(), "\n") {
		if strings.HasPrefix(line, "data: ") {
			if a, ok := aiUsageCost([]byte(line[6:]), config.AIPrice{Input: 2, CachedInput: 1, Output: 3}); ok {
				paid = true
				if a.Input != 100 || a.Cached != 40 || a.Output != 20 || a.Spent != 220 {
					t.Fatal(a)
				}
			}
		}
	}
	if !paid {
		t.Fatal("usage lost")
	}
	for _, ending := range []string{"", strings.ReplaceAll(completed, "completed", "incomplete"), strings.ReplaceAll(completed, "completed", "failed")} {
		out.Reset()
		err := translateAIResponses(strings.NewReader(prefix+"data: "+ending+"\n\n"), true, &out)
		if err == nil || strings.Contains(out.String(), "[DONE]") || strings.Contains(out.String(), "tool_calls") {
			t.Fatal("unsafe incomplete stream", err, out.String())
		}
	}
}
func TestResponsesNonStreamingAndErrors(t *testing.T) {
	var out bytes.Buffer
	err := translateAIResponses(strings.NewReader(`{"id":"resp","model":"gpt-6.1-sol","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}],"usage":{"input_tokens":3,"output_tokens":2}}`), false, &out)
	if err != nil || !strings.Contains(out.String(), `"content":"ok"`) {
		t.Fatal(err, out.String())
	}
	cases := []struct {
		status    int
		raw, code string
	}{{400, `{"error":{"param":"reasoning_effort","message":"use /v1/responses secret"}}`, "ai_protocol_unsupported"}, {429, `{"error":{"code":"insufficient_quota","message":"secret"}}`, "ai_provider_quota"}, {404, `{"error":{"code":"model_not_found"}}`, "ai_model_unavailable"}, {401, `secret`, "ai_provider_authentication"}, {502, `<html>secret</html>`, "ai_upstream_error"}}
	for _, c := range cases {
		if got := aiProviderError(c.status, []byte(c.raw)); got != c.code {
			t.Fatal(got, c.code)
		}
	}
}

type responsesTestTransport func(*http.Request) (*http.Response, error)

func (f responsesTestTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestResponsesGatewaySettlesUsage(t *testing.T) {
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(context.Background(), config.ModeRemote, filepath.Join(t.TempDir(), "responses.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, _ := db.DB()
	defer sqlDB.Close()
	resources, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	cfg.AIGateway = &config.AIGateway{DefaultModel: "sol", DailyRequests: 100, DailyQuotaPoints: 500000, Models: map[string]config.AIModel{"sol": {Provider: "openai", Endpoint: "https://api.openai.com/v1", APIKey: "test-only", Model: "gpt-6.1-sol", MaxOutputTokens: 4096, Pricing: config.AIPrice{Input: 2, CachedInput: 1, Output: 3}}}}
	original := aiHTTPClient
	defer func() { aiHTTPClient = original }()
	aiHTTPClient = &http.Client{Transport: responsesTestTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/v1/responses" {
			t.Fatal(r.URL.Path)
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		if body["store"] != false || body["input"] == nil {
			t.Fatal(body)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[],\"usage\":{\"input_tokens\":100,\"output_tokens\":20,\"input_tokens_details\":{\"cached_tokens\":40}}}}\n\n")), Header: make(http.Header)}, nil
	})}
	a := New(cfg, nil, resources)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/v1/ai/chat/completions", strings.NewReader(`{"messages":[{"role":"user","content":"test"}],"stream":true}`))
	a.aiCompletions(w, r, model.User{ID: "responses-user"}, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), "[DONE]") {
		t.Fatal(w.Code, w.Body.String())
	}
	var row model.Setting
	if err := db.Where("`key` LIKE ?", "ai.ledger.responses-user.%").First(&row).Error; err != nil {
		t.Fatal(err)
	}
	var entry aiLedgerEntry
	if err := json.Unmarshal([]byte(row.Value), &entry); err != nil {
		t.Fatal(err)
	}
	if entry.Status != "settled" || entry.Usage.Spent != 220 || entry.Usage.Input != 100 {
		t.Fatal(entry)
	}
}
