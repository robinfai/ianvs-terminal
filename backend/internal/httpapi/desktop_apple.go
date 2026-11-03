package httpapi

import (
	"crypto/sha256"
	"crypto/subtle"
	"net/http"
	"net/url"
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
	}
	if err := decodeBody(w, r, 40<<10, &input); err != nil {
		writeDecodeError(w, err)
		return
	}
	flows := a.desktopAppleFlows
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
		authorization := url.URL{Scheme: "https", Host: "appleid.apple.com", Path: "/auth/authorize"}
		authorization.RawQuery = url.Values{
			"client_id": {a.cfg.AppleWeb.ClientID}, "redirect_uri": {a.cfg.AppleWeb.RedirectURI},
			"response_type": {"code id_token"}, "response_mode": {"form_post"},
			"state": {id}, "nonce": {nonce},
		}.Encode()
		writeJSON(w, 200, map[string]string{"id": id, "secret": secret, "nonce": nonce, "authorization_url": authorization.String()})
	case "poll", "cancel":
		flow, ok := flows.pending[input.ID]
		if !ok {
			writeError(w, 410, "oauth_expired", "Sign-in expired; please retry")
			return
		}
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

	default:
		http.NotFound(w, r)
	}
}

// Apple posts to the existing registered HTTPS return URL. The custom-scheme
// redirect carries only a flow identifier, never an ID token or retrieval secret.
func (a *API) desktopAppleCallback(w http.ResponseWriter, r *http.Request) {
	if a.cfg.AppleWeb == nil {
		http.NotFound(w, r)
		return
	}
	registered, err := url.Parse(a.cfg.AppleWeb.RedirectURI)
	if err != nil || r.URL.Path != registered.Path && !(r.URL.Path == "/" && registered.Path == "") {
		http.NotFound(w, r)
		return
	}
	if !a.allowOAuth(w, r) {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 40<<10)
	if err := r.ParseForm(); err != nil {
		writeError(w, 400, "invalid_callback", "Invalid callback")
		return
	}
	id := r.PostForm.Get("state")
	flows := a.desktopAppleFlows
	flows.Lock()
	flow, ok := flows.pending[id]
	flows.Unlock()
	if !ok || !time.Now().Before(flow.expires) {
		writeError(w, 410, "oauth_expired", "Sign-in expired")
		return
	}
	callback := url.URL{Scheme: "work.ianvs.trail.auth", Host: "apple", RawQuery: url.Values{"state": {id}}.Encode()}
	if r.PostForm.Get("error") != "" {
		callback.RawQuery += "&error=cancelled"
		http.Redirect(w, r, callback.String(), http.StatusSeeOther)
		return
	}
	token := r.PostForm.Get("id_token")
	_, err = a.appleVerifier.Verify(r.Context(), token, flow.nonce, []string{a.cfg.AppleWeb.ClientID})
	if err != nil {
		callback.RawQuery += "&error=invalid_identity"
		http.Redirect(w, r, callback.String(), http.StatusSeeOther)
		return
	}
	flows.Lock()
	current, exists := flows.pending[id]
	if !exists || !time.Now().Before(current.expires) || current.token != "" {
		flows.Unlock()
		writeError(w, 410, "oauth_expired", "Sign-in expired or completed")
		return
	}
	current.token = token
	flows.pending[id] = current
	flows.Unlock()
	http.Redirect(w, r, callback.String(), http.StatusSeeOther)
}
