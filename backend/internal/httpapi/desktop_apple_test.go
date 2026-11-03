package httpapi

import (
	"crypto/sha256"
	"ianvs-terminal/backend/internal/config"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestDesktopAppleRetrievalIsSecretBoundSingleUseAndExpiring(t *testing.T) {
	secret := strings.Repeat("s", 43)
	a := &API{
		cfg:                  config.Config{Mode: config.ModeRemote, AllowInsecureSensitiveTransport: true, AppleWeb: &config.AppleWeb{ClientID: "test.web"}},
		anonymousAuthLimiter: newAnonymousAuthRateLimiter(),
		desktopAppleFlows: &desktopAppleFlows{pending: map[string]desktopAppleFlow{
			"flow":    {secret: sha256.Sum256([]byte(secret)), nonce: "nonce", token: "verified-token", expires: time.Now().Add(time.Minute)},
			"expired": {secret: sha256.Sum256([]byte(secret)), token: "expired-token", expires: time.Now().Add(-time.Second)},
		}},
	}
	call := func(action, id, key string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "https://example.com/v1/auth/apple/desktop/"+action, strings.NewReader(`{"id":"`+id+`","secret":"`+key+`"}`))
		r.Header.Set("Content-Type", "application/json")
		r.SetPathValue("action", action)
		w := httptest.NewRecorder()
		a.desktopApple(w, r)
		return w
	}
	if w := call("poll", "flow", strings.Repeat("x", 43)); w.Code != 401 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := call("poll", "flow", secret); w.Code != 200 || !strings.Contains(w.Body.String(), "verified-token") {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := call("poll", "flow", secret); w.Code != 410 {
		t.Fatal("replayed token", w.Code)
	}
	if w := call("poll", "expired", secret); w.Code != 410 {
		t.Fatal("expired token", w.Code)
	}
}
