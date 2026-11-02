package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gorm.io/gorm/clause"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

var aiHTTPClient = &http.Client{Timeout: 120 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func (a *API) aiModels(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	g := a.cfg.AIGateway
	if g == nil {
		writeError(w, 503, "ai_unavailable", "AI gateway is not configured")
		return
	}
	models := []map[string]any{}
	for alias, m := range g.Models {
		if !g.Allows(user.ID, alias) {
			continue
		}
		m.Pricing = g.PriceFor(user.ID, alias)
		models = append(models, map[string]any{"id": publicAIModelID(g, alias), "provider": m.Provider, "pricing": m.Pricing})
	}
	quota := g.RequestLimit(user.ID)
	writeJSON(w, 200, map[string]any{"data": models, "default_model": publicAIModelID(g, g.DefaultModel), "daily_requests": quota, "daily_quota_points": a.aiBudget(user.ID) / 2000, "daily_budget_nano_usd": a.aiBudget(user.ID), "quota_unit": "nano_usd", "quota_points_per_usd": 500000, "reset_timezone": "UTC"})
}

// Durable compare-and-swap works across SQLite/MySQL and multiple replicas.
// Settings are server-owned and inaccessible through the resource API.
func (a *API) reserveAIRequest(ctx context.Context, user string, limit int) (bool, error) {
	if limit <= 0 {
		return false, nil
	}
	key := "ai.requests." + time.Now().UTC().Format("2006-01-02") + "." + user
	db := a.store.DB().WithContext(ctx)
	row := model.Setting{Key: key, Value: "0"}
	if err := db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error; err != nil {
		return false, err
	}
	for i := 0; i < 32; i++ {
		if err := db.Where("`key` = ?", key).First(&row).Error; err != nil {
			return false, err
		}
		count, err := strconv.Atoi(row.Value)
		if err != nil || count < 0 {
			return false, errors.New("invalid quota counter")
		}
		if count >= limit {
			return false, nil
		}
		result := db.Model(&model.Setting{}).Where("`key` = ? AND value = ?", key, row.Value).Updates(map[string]any{"value": strconv.Itoa(count + 1), "updated_at": time.Now().UTC()})
		if result.Error != nil {
			return false, result.Error
		}
		if result.RowsAffected == 1 {
			return true, nil
		}
	}
	return false, errors.New("quota contention")
}

func (a *API) aiCompletions(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	// Traverse the observability wrapper for streaming flushes and give model
	// generation its own deadline instead of the ordinary CRUD write timeout.
	responseControl := http.NewResponseController(w)
	_ = responseControl.SetWriteDeadline(time.Now().Add(125 * time.Second))
	g := a.cfg.AIGateway
	if g == nil {
		writeError(w, 503, "ai_unavailable", "AI gateway is not configured")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var body map[string]json.RawMessage
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(&body); err != nil || body == nil {
		writeError(w, 400, "invalid_request", "Invalid completion request")
		return
	}
	var extra any
	if dec.Decode(&extra) != io.EOF {
		writeError(w, 400, "invalid_request", "Expected one JSON object")
		return
	}
	var alias string
	if v, ok := body["model"]; ok && json.Unmarshal(v, &alias) != nil {
		writeError(w, 400, "invalid_model", "Invalid model")
		return
	}
	if alias == "" || alias == "default" {
		alias = g.DefaultModel
	}
	// Keep accepting saved legacy aliases; new catalog IDs identify concrete models.
	if _, legacy := g.Models[alias]; !legacy {
		for candidate := range g.Models {
			if publicAIModelID(g, candidate) == alias {
				alias = candidate
				break
			}
		}
	}
	m, ok := g.Models[alias]
	if !ok {
		writeError(w, 400, "invalid_model", "Model is not available")
		return
	}
	if !g.Allows(user.ID, alias) {
		writeError(w, 403, "ai_model_forbidden", "Model is not allowed by your AI policy")
		return
	}
	m.Pricing = g.PriceFor(user.ID, alias)
	var messages []json.RawMessage
	if json.Unmarshal(body["messages"], &messages) != nil || len(messages) == 0 {
		writeError(w, 400, "invalid_messages", "Messages are required")
		return
	}
	var stream bool
	if v, ok := body["stream"]; ok && json.Unmarshal(v, &stream) != nil {
		writeError(w, 400, "invalid_stream", "Invalid stream option")
		return
	}
	// Only forward the supported protocol fields; callers cannot set a provider,
	// endpoint, credential, storage policy, or bypass server output limits.
	payload := map[string]json.RawMessage{}
	for _, key := range []string{"messages", "tools", "tool_choice", "parallel_tool_calls", "stream", "reasoning_effort"} {
		if v, ok := body[key]; ok {
			payload[key] = v
		}
	}
	payload["model"], _ = json.Marshal(m.Model)
	capKey := "max_completion_tokens"
	if m.Provider == "deepseek" {
		capKey = "max_tokens"
	}
	payload[capKey], _ = json.Marshal(m.MaxOutputTokens)
	if stream {
		payload["stream_options"] = json.RawMessage(`{"include_usage":true}`)
	}
	if m.Provider == "deepseek" {
		payload["thinking"] = json.RawMessage(`{"type":"disabled"}`)
	}
	// Only text and function tools have configured prices. Reject multimodal inputs.
	for _, raw := range messages {
		var msg map[string]json.RawMessage
		if json.Unmarshal(raw, &msg) != nil {
			writeError(w, 400, "invalid_messages", "Invalid message")
			return
		}
		if content, ok := msg["content"]; ok && string(content) != "null" {
			var value string
			if json.Unmarshal(content, &value) != nil {
				var parts []struct {
					Type string `json:"type"`
					Text string `json:"text"`
				}
				if json.Unmarshal(content, &parts) != nil {
					writeError(w, 400, "invalid_messages", "Text messages only")
					return
				}
				for _, part := range parts {
					if part.Type != "text" {
						writeError(w, 400, "unsupported_content", "Only text input is priced")
						return
					}
				}
			}
		}
	}

	useResponses := usesAIResponses(m.Provider, m.Endpoint)
	path := "/chat/completions"
	if useResponses {
		var err error
		payload, err = aiResponsesPayload(payload)
		if err != nil {
			writeError(w, 400, "invalid_request", "Invalid model input or tools")
			return
		}
		path = "/responses"
	}
	encoded, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, strings.TrimRight(m.Endpoint, "/")+path, bytes.NewReader(encoded))
	if err != nil {
		writeError(w, 503, "ai_unavailable", "Invalid gateway configuration")
		return
	}
	// Reserve a conservative UTF-8 byte estimate plus protocol overhead, and
	// the server output cap. This is an estimate, not a tokenizer guarantee.
	// Exact upstream usage replaces it; missing usage remains visibly reserved.
	inputBound := int64(len(encoded) + 4096 + len(messages)*32)
	if inputBound > 100000 {
		writeError(w, 400, "context_too_large", "Gateway text context limit exceeded")
		return
	}
	event, retry := a.aiLimiter.reserve(user.ID, g.Users[user.ID].RateLimits(), inputBound+int64(m.MaxOutputTokens), time.Now())
	if event == nil {
		w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
		writeError(w, 429, "ai_rate_limited", "AI request or token rate exceeded; retry later")
		return
	}
	tokenUsage := int64(0)
	defer func() {
		if tokenUsage >= 0 {
			a.aiLimiter.settle(event, tokenUsage)
		}
	}()
	reserved := inputBound*m.Pricing.Input + int64(m.MaxOutputTokens)*m.Pricing.Output
	entry, err := a.reserveAISpend(r.Context(), user.ID, alias, m, reserved)
	if err != nil {
		if errors.Is(err, errAIBudget) {
			w.Header().Set("X-AI-Quota-Exhausted", "true")
			w.Header().Set("Retry-After", strconv.Itoa(int(time.Until(time.Now().UTC().Truncate(24*time.Hour).Add(24*time.Hour)).Seconds())+1))
			writeError(w, 429, "ai_quota_exceeded", "Insufficient daily AI quota for this request")
		} else {
			writeError(w, 503, "quota_unavailable", "Could not reserve AI quota")
		}
		return
	}
	w.Header().Set("X-AI-Request-ID", entry.ID)
	var actual aiAccount
	outcome := "refunded"
	var settled bool
	defer func() {
		if !settled {
			return
		}
		tokenUsage = actual.Input + actual.Output
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := a.settleAISpend(ctx, user.ID, entry.ID, actual, outcome); err != nil {
			slog.Error("AI settlement pending", "request_id", entry.ID, "error", err)
		}
	}()
	quota := g.RequestLimit(user.ID)
	admitted, err := a.reserveAIRequest(r.Context(), user.ID, quota)
	if err != nil {
		settled = true
		writeError(w, 503, "quota_unavailable", "Could not check AI quota")
		return
	}
	if !admitted {
		settled = true
		w.Header().Set("X-AI-Quota-Exhausted", "true")
		w.Header().Set("Retry-After", strconv.Itoa(int(time.Until(time.Now().UTC().Truncate(24*time.Hour).Add(24*time.Hour)).Seconds())+1))
		writeError(w, 429, "ai_quota_exceeded", "Daily AI request quota exhausted")
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+m.APIKey)
	client, closeIdle, err := providerHTTPClient(m.ProxyURL, m.ProxyUsername, m.ProxyPassword)
	if err != nil {
		writeError(w, 503, "gateway_configuration_unavailable", "Invalid provider proxy configuration")
		return
	}
	defer closeIdle()
	tokenUsage = -1 // Unknown upstream usage retains the conservative reservation.
	response, err := client.Do(req)
	if err != nil {
		writeError(w, 502, "ai_upstream_unavailable", "AI provider is unavailable")
		return
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		settled = true // Explicit rejection: no generated usage.
		writeAIProviderError(w, response, entry.ID, m.Provider, m.Model)
		return
	}
	if useResponses {
		response.Body = aiResponsesBody(response.Body, stream)
		defer response.Body.Close()
	}
	w.Header().Set("Cache-Control", "no-store")
	if stream {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("X-Accel-Buffering", "no")
	} else {
		w.Header().Set("Content-Type", "application/json")
	}
	// Bound streamed and non-streamed output, propagate disconnect cancellation,
	// and flush each chunk rather than buffering the entire model response.
	reader := io.LimitReader(response.Body, 8<<20)
	buf := make([]byte, 32<<10)
	var capture bytes.Buffer
	var ssePending []byte
	observe := func(chunk []byte) {
		if !stream {
			capture.Write(chunk)
			return
		}
		ssePending = append(ssePending, chunk...)
		for {
			at := bytes.IndexByte(ssePending, '\n')
			if at < 0 {
				break
			}
			line := bytes.TrimSpace(ssePending[:at])
			ssePending = ssePending[at+1:]
			if bytes.HasPrefix(line, []byte("data:")) {
				if usage, ok := aiUsageCost(bytes.TrimSpace(line[5:]), m.Pricing); ok {
					actual = usage
					outcome = "settled"
					settled = true
				}
			}
		}
	}
	for {
		n, e := reader.Read(buf)
		if n > 0 {
			observe(buf[:n])
			if _, err := w.Write(buf[:n]); err != nil {
				return
			}
			if stream {
				if err := responseControl.Flush(); err != nil {
					return
				}
			}
		}
		if e != nil {
			if !stream && e == io.EOF {
				actual, settled = aiUsageCost(capture.Bytes(), m.Pricing)
				if settled {
					outcome = "settled"
				}
			}
			return
		}
	}
}

// Concrete model IDs are stable for unique routes. Qualify duplicate models or
// collisions with legacy aliases so selection never silently changes provider.
func publicAIModelID(g *config.AIGateway, alias string) string {
	m, ok := g.Models[alias]
	if !ok {
		return alias
	}
	for other, candidate := range g.Models {
		if other != alias && (candidate.Model == m.Model || other == m.Model) {
			return m.Model + "@" + alias
		}
	}
	return m.Model
}
