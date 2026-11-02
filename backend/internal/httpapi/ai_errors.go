package httpapi

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"
)

// Return only an allowlisted diagnosis, never an upstream message (it can
// contain credentials, prompts or proxy details). Request IDs correlate logs.
func aiProviderError(status int, body []byte) string {
	var envelope struct {
		Error struct {
			Code    string `json:"code"`
			Type    string `json:"type"`
			Param   string `json:"param"`
			Message string `json:"message"`
		} `json:"error"`
	}
	_ = json.Unmarshal(body, &envelope)
	e := envelope.Error
	if e.Code == "insufficient_quota" {
		return "ai_provider_quota"
	}
	if e.Code == "model_not_found" {
		return "ai_model_unavailable"
	}
	if e.Code == "context_length_exceeded" {
		return "context_too_large"
	}
	if e.Param == "reasoning_effort" && strings.Contains(e.Message, "/v1/responses") {
		return "ai_protocol_unsupported"
	}
	switch status {
	case 401, 403:
		return "ai_provider_authentication"
	case 429:
		return "ai_provider_rate_limited"
	case 400, 422:
		return "ai_request_rejected"
	default:
		return "ai_upstream_error"
	}
}
func writeAIProviderError(w http.ResponseWriter, response *http.Response, requestID, provider, model string) {
	body, _ := io.ReadAll(io.LimitReader(response.Body, 64<<10))
	code := aiProviderError(response.StatusCode, body)
	slog.Warn("AI upstream rejected request", "request_id", requestID, "provider", provider, "model", model, "status", response.StatusCode, "code", code)
	writeError(w, 502, code, "AI provider could not complete this request")
}
