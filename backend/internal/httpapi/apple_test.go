package httpapi_test

import (
	"encoding/json"
	"ianvs-terminal/backend/internal/config"
	"net/http"
	"testing"
)

func TestAppleEndpointsRequireExplicitConfigurationAndSecureTransport(t *testing.T) {
	cfg, _, disabled := testAPI(t, config.ModeRemote)
	for _, path := range []string{"/v1/auth/apple/challenge", "/v1/auth/apple/begin"} {
		result := request(t, disabled, http.MethodPost, path, map[string]any{}, nil)
		assertTypedError(t, result, http.StatusNotFound, "apple_unavailable")
	}
	cfg.AppleClientIDs = []string{"work.ianvs.trail"}
	cfg.AllowInsecureSensitiveTransport = false
	secure := testAPIHandler(t, cfg)
	for _, path := range []string{"/v1/auth/apple/challenge", "/v1/auth/apple/begin"} {
		result := request(t, secure, http.MethodPost, path, map[string]any{}, nil)
		assertTypedError(t, result, http.StatusBadRequest, "secure_transport_required")
	}
	cfg.AllowInsecureSensitiveTransport = true
	enabled := testAPIHandler(t, cfg)
	response := request(t, enabled, http.MethodPost, "/v1/auth/apple/challenge", map[string]any{}, nil)
	if response.Code != http.StatusOK {
		t.Fatal(response.Body.String())
	}
	var challenge struct {
		Nonce string `json:"nonce"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &challenge); err != nil || len(challenge.Nonce) != 43 {
		t.Fatalf("invalid challenge: %v", err)
	}
	response = request(t, enabled, http.MethodPost, "/v1/auth/apple/begin", map[string]any{"nonce": challenge.Nonce, "identity_token": "forged-token"}, nil)
	assertTypedError(t, response, http.StatusUnauthorized, "invalid_apple_identity")
}
