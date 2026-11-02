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

func TestDesktopAppleStartAndRejectForgedCompletion(t *testing.T) {
	cfg, _, _ := testAPI(t, config.ModeRemote)
	cfg.AppleClientIDs = []string{"work.ianvs.trail.web"}
	cfg.AppleWeb = &config.AppleWeb{ClientID: "work.ianvs.trail.web", RedirectURI: "https://example.com/"}
	handler := testAPIHandler(t, cfg)
	start := request(t, handler, http.MethodPost, "/v1/auth/apple/desktop/start", map[string]any{}, nil)
	var flow map[string]string
	if start.Code != 200 || json.Unmarshal(start.Body.Bytes(), &flow) != nil || len(flow["id"]) != 43 || len(flow["secret"]) != 43 || len(flow["nonce"]) != 43 || flow["id"] == flow["secret"] {
		t.Fatal(start.Code, start.Body.String())
	}
	forged := request(t, handler, http.MethodPost, "/v1/auth/apple/desktop/complete", map[string]any{"id": flow["id"], "identity_token": "forged"}, nil)
	assertTypedError(t, forged, http.StatusUnauthorized, "invalid_apple_identity")
	pending := request(t, handler, http.MethodPost, "/v1/auth/apple/desktop/poll", map[string]any{"id": flow["id"], "secret": flow["secret"]}, nil)
	if pending.Code != 200 || !strings.Contains(pending.Body.String(), `"pending":true`) {
		t.Fatal(pending.Body.String())
	}
	request(t, handler, http.MethodPost, "/v1/auth/apple/desktop/cancel", map[string]any{"id": flow["id"], "secret": flow["secret"]}, nil)
	expired := request(t, handler, http.MethodPost, "/v1/auth/apple/desktop/info", map[string]any{"id": flow["id"]}, nil)
	assertTypedError(t, expired, 410, "oauth_expired")
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

func TestOAuthRequestShapeReachesIdentityVerification(t *testing.T) {
	cfg, _, _ := testAPI(t, config.ModeRemote)
	cfg.AllowInsecureSensitiveTransport = true
	cfg.GoogleClientIDs = []string{"trail.apps.googleusercontent.com"}
	handler := testAPIHandler(t, cfg)
	body := map[string]any{"provider": "google", "identity_token": "forged-token", "nonce": strings.Repeat("a", 43), "action": "link", "device_id": strings.Repeat("b", 64), "replace_oldest": false, "username": "", "password": "", "link": map[string]any{"provider": "apple", "identity_token": "other-token", "nonce": strings.Repeat("c", 43)}}
	response := request(t, handler, http.MethodPost, "/v1/auth/oauth/begin", body, nil)
	assertTypedError(t, response, http.StatusUnauthorized, "invalid_apple_identity")
	body["unknown_field"] = true
	response = request(t, handler, http.MethodPost, "/v1/auth/oauth/begin", body, nil)
	assertTypedError(t, response, http.StatusBadRequest, "invalid_json")
}

func TestPasswordAuthenticationDisabledStillAllowsOAuthChallenge(t *testing.T) {
	cfg, _, _ := testAPI(t, config.ModeRemote)
	cfg.PasswordAuthEnabled = false
	handler := testAPIHandler(t, cfg)
	for _, path := range []string{"/v1/auth/login/begin", "/v1/auth/register/begin", "/v1/auth/register/complete"} {
		response := request(t, handler, http.MethodPost, path, map[string]any{}, nil)
		assertTypedError(t, response, http.StatusForbidden, "password_auth_disabled")
	}
	response := request(t, handler, http.MethodPost, "/v1/auth/oauth/challenge", map[string]any{}, nil)
	if response.Code != http.StatusOK {
		t.Fatal(response.Body.String())
	}
	response = request(t, handler, http.MethodPost, "/v1/auth/identities", map[string]any{}, nil)
	assertTypedError(t, response, http.StatusUnauthorized, "unauthorized")
}

func TestAuthenticatedIdentityEndpointsUseSessionAndRejectForgedProof(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeRemote)
	session := register(t, handler, "link-test", "link-test-password", "")
	headers := map[string]string{"Authorization": "Bearer " + session.Token}
	response := request(t, handler, http.MethodGet, "/v1/auth/identities", nil, headers)
	if response.Code != http.StatusOK || strings.TrimSpace(response.Body.String()) != "{\"providers\":[]}" {
		t.Fatal(response.Body.String())
	}
	proof := map[string]any{"provider": "google", "identity_token": "forged-token", "nonce": strings.Repeat("a", 43)}
	response = request(t, handler, http.MethodPost, "/v1/auth/identities", proof, headers)
	assertTypedError(t, response, http.StatusUnauthorized, "invalid_apple_identity")
	proof["user_id"] = "another-account"
	response = request(t, handler, http.MethodPost, "/v1/auth/identities", proof, headers)
	assertTypedError(t, response, http.StatusBadRequest, "invalid_json")
}
