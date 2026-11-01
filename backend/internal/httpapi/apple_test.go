package httpapi_test

import (
	"encoding/json"
	"ianvs-terminal/backend/internal/config"
	"net/http"
	"strings"
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

func TestAppleWebPublicConfigurationAndScopedSDKPolicy(t *testing.T) {
	cfg, _, _ := testAPI(t, config.ModeRemote)
	cfg.AppleClientIDs = []string{"work.ianvs.trail", "work.ianvs.trail.web"}
	cfg.AppleWeb = &config.AppleWeb{ClientID: "work.ianvs.trail.web", RedirectURI: "https://example.com/"}
	handler := testAPIHandler(t, cfg)
	response := request(t, handler, http.MethodGet, "/healthz", nil, nil)
	var body struct {
		AppleWeb *config.AppleWeb `json:"apple_web"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || body.AppleWeb == nil || body.AppleWeb.ClientID != cfg.AppleWeb.ClientID {
		t.Fatal("missing public web configuration")
	}
	root := request(t, handler, http.MethodGet, "/", nil, nil)
	if !strings.Contains(root.Header().Get("Content-Security-Policy"), "https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js") {
		t.Fatal("Apple SDK blocked")
	}
	if strings.Contains(response.Header().Get("Content-Security-Policy"), "cdn-apple") {
		t.Fatal("SDK permission leaked to API")
	}
	cfg.AppleWeb = nil
	root = request(t, testAPIHandler(t, cfg), http.MethodGet, "/", nil, nil)
	if strings.Contains(root.Header().Get("Content-Security-Policy"), "cdn-apple") {
		t.Fatal("disabled Apple web still allows third party scripts")
	}
}
