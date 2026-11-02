package httpapi

import (
	"crypto/sha256"
	"crypto/subtle"
	"net/http"
	"sync"
	"time"

	"ianvs-terminal/backend/internal/identity"
)

// The browser knows only the flow ID. Only the initiating app receives the
// independent retrieval secret; neither identity tokens nor that secret go in URLs.
type desktopAppleFlow struct {
	secret  [32]byte
	nonce   string
	token   string
	expires time.Time
}
type desktopAppleFlows struct {
	sync.Mutex
	pending map[string]desktopAppleFlow
}

func (a *API) desktopApple(w http.ResponseWriter, r *http.Request) {
	if !a.allowOAuth(w, r) {
		return
	}
	if a.cfg.AppleWeb == nil {
		writeError(w, 404, "oauth_unavailable", "Apple web sign-in is unavailable")
		return
	}
	var input struct {
		ID     string `json:"id"`
		Secret string `json:"secret"`
		Token  string `json:"identity_token"`
	}
	if err := decodeBody(w, r, 40<<10, &input); err != nil {
		writeDecodeError(w, err)
		return
	}
	flows := &a.desktopAppleFlows
	flows.Lock()
	defer flows.Unlock()
	now := time.Now()
	for id, flow := range flows.pending {
		if !now.Before(flow.expires) {
			delete(flows.pending, id)
		}
	}
	switch r.PathValue("action") {
	case "start":
		if len(flows.pending) >= 1024 {
			writeError(w, 429, "auth_busy", "Please retry later")
			return
		}
		id, err := identity.Secret(32)
		if err != nil {
			a.writeServiceError(w, err)
			return
		}
		secret, err := identity.Secret(32)
		if err != nil {
			a.writeServiceError(w, err)
			return
		}
		nonce, err := a.auth.CreateAppleChallenge(r.Context())
		if err != nil {
			a.writeServiceError(w, err)
			return
		}
		flows.pending[id] = desktopAppleFlow{secret: sha256.Sum256([]byte(secret)), nonce: nonce, expires: now.Add(5 * time.Minute)}
		writeJSON(w, 200, map[string]string{"id": id, "secret": secret, "nonce": nonce})
	case "info", "complete", "poll", "cancel":
		flow, ok := flows.pending[input.ID]
		if !ok {
			writeError(w, 410, "oauth_expired", "Sign-in expired; please retry")
			return
		}
		switch r.PathValue("action") {
		case "info":
			writeJSON(w, 200, map[string]any{"nonce": flow.nonce, "apple_web": a.cfg.AppleWeb})
		case "complete":
			if flow.token != "" {
				writeError(w, 409, "oauth_completed", "Already completed")
				return
			}
			// Restrict this bridge to the configured web audience, not arbitrary native IDs.
			// Do not hold the map lock while fetching Apple's verification keys.
			flows.Unlock()
			_, err := a.appleVerifier.Verify(r.Context(), input.Token, flow.nonce, []string{a.cfg.AppleWeb.ClientID})
			flows.Lock()
			if err != nil {
				a.writeServiceError(w, err)
				return
			}
			current, exists := flows.pending[input.ID]
			if !exists || !time.Now().Before(current.expires) {
				writeError(w, 410, "oauth_expired", "Sign-in expired")
				return
			}
			if current.token != "" {
				writeError(w, 409, "oauth_completed", "Already completed")
				return
			}
			current.token = input.Token
			flows.pending[input.ID] = current
			writeJSON(w, 200, map[string]bool{"completed": true})
		default:
			digest := sha256.Sum256([]byte(input.Secret))
			if len(input.Secret) != 43 || subtle.ConstantTimeCompare(digest[:], flow.secret[:]) != 1 {
				writeError(w, 401, "unauthorized", "Invalid retrieval secret")
				return
			}
			if r.PathValue("action") == "cancel" {
				delete(flows.pending, input.ID)
				writeJSON(w, 200, map[string]bool{"cancelled": true})
				return
			}
			if flow.token == "" {
				writeJSON(w, 200, map[string]bool{"pending": true})
				return
			}
			delete(flows.pending, input.ID)
			writeJSON(w, 200, map[string]string{"identity_token": flow.token, "nonce": flow.nonce})
		}
	default:
		http.NotFound(w, r)
	}
}
