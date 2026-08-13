package httpapi_test

import (
	"net/http"
	"regexp"
	"strings"
	"testing"

	"ianvs-terminal/backend/internal/config"
)

func TestEmbeddedWebUIRoutesDoNotShadowTheAPI(t *testing.T) {
	cfg, _, _ := testAPI(t, config.ModeLocal)
	cfg.LocalAccessToken = "parent-owned-token"
	handler := testAPIHandler(t, cfg)

	root := request(t, handler, http.MethodGet, "/", nil, nil)
	if root.Code != http.StatusOK ||
		!strings.Contains(root.Body.String(), "Ianvs SSH Profile Vault") {
		t.Fatalf("root status = %d, body = %s", root.Code, root.Body.String())
	}
	if got := root.Header().Get("Content-Security-Policy"); !strings.Contains(got, "default-src 'self'") ||
		!strings.Contains(got, "frame-ancestors 'none'") {
		t.Fatalf("root Content-Security-Policy = %q", got)
	}

	deepLink := request(t, handler, http.MethodGet, "/profiles", nil, nil)
	if deepLink.Code != http.StatusOK || deepLink.Body.String() != root.Body.String() {
		t.Fatalf("deep link status = %d, body = %s", deepLink.Code, deepLink.Body.String())
	}

	assetMatch := regexp.MustCompile(`src="/(assets/[^"]+\.js)"`).FindStringSubmatch(root.Body.String())
	if len(assetMatch) != 2 {
		t.Fatalf("index omitted hashed JavaScript asset: %s", root.Body.String())
	}
	asset := request(t, handler, http.MethodGet, "/"+assetMatch[1], nil, nil)
	if asset.Code != http.StatusOK ||
		asset.Header().Get("Cache-Control") != "public, max-age=31536000, immutable" {
		t.Fatalf(
			"asset status/cache = %d/%q",
			asset.Code,
			asset.Header().Get("Cache-Control"),
		)
	}

	for _, target := range []string{"/v1", "/v1/not-a-real-endpoint", "/healthz/missing"} {
		api := request(t, handler, http.MethodGet, target, nil, nil)
		if api.Code != http.StatusUnauthorized ||
			strings.Contains(api.Body.String(), "<div id=\"root\">") {
			t.Fatalf(
				"API route %q was shadowed: status = %d, body = %s",
				target,
				api.Code,
				api.Body.String(),
			)
		}
	}
}

func TestEmbeddedWebUIRejectsNonGETFallbacks(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeRemote)
	response := request(t, handler, http.MethodPost, "/profiles", nil, nil)
	if response.Code != http.StatusNotFound || strings.Contains(response.Body.String(), "<div id=\"root\">") {
		t.Fatalf("POST fallback status = %d, body = %s", response.Code, response.Body.String())
	}
}
