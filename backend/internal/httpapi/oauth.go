package httpapi

import (
	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
	"net/http"
)

func (a *API) allowOAuth(w http.ResponseWriter, r *http.Request) bool {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, 404, "oauth_unavailable", "OAuth is unavailable")
		return false
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, 400, "secure_transport_required", "OAuth requires HTTPS")
		return false
	}
	return a.allowAnonymousAuthRequest(w, r)
}

func (a *API) oauthChallenge(w http.ResponseWriter, r *http.Request) {
	if !a.allowOAuth(w, r) {
		return
	}
	nonce, err := a.auth.CreateAppleChallenge(r.Context())
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, 200, map[string]string{"nonce": nonce})
}

type oauthProof struct {
	Provider      string `json:"provider"`
	IdentityToken string `json:"identity_token"`
	Nonce         string `json:"nonce"`
}

func (a *API) verifyOAuth(r *http.Request, proof oauthProof) (string, error) {
	switch proof.Provider {
	case "apple":
		return a.appleVerifier.Verify(r.Context(), proof.IdentityToken, proof.Nonce, a.cfg.AppleClientIDs)
	case "google":
		return a.googleVerifier.Verify(r.Context(), proof.IdentityToken, proof.Nonce, a.cfg.GoogleClientIDs)
	default:
		return "", auth.ErrAppleIdentity
	}
}

func (a *API) beginOAuthLogin(w http.ResponseWriter, r *http.Request) {
	if !a.allowOAuth(w, r) {
		return
	}
	var request struct {
		Provider      string      `json:"provider"`
		IdentityToken string      `json:"identity_token"`
		Nonce         string      `json:"nonce"`
		Action        string      `json:"action"`
		DeviceID      string      `json:"device_id"`
		Username      string      `json:"username"`
		Password      string      `json:"password"`
		Link          *oauthProof `json:"link"`
		ReplaceOldest bool        `json:"replace_oldest"`
	}
	if err := decodeBody(w, r, 40<<10, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	subject, err := a.verifyOAuth(r, oauthProof{Provider: request.Provider, IdentityToken: request.IdentityToken, Nonce: request.Nonce})
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	input := auth.OAuthLogin{Provider: request.Provider, Subject: subject, Nonce: request.Nonce, Action: request.Action, Username: request.Username, Password: request.Password, AllowRegistration: a.cfg.AllowRegistration, ReplaceOldest: request.ReplaceOldest}
	if request.Link != nil {
		input.LinkSubject, err = a.verifyOAuth(r, *request.Link)
		if err != nil {
			a.writeServiceError(w, err)
			return
		}
		input.LinkProvider, input.LinkNonce = request.Link.Provider, request.Link.Nonce
	}
	operation, err := a.auth.BeginOAuthLogin(auth.WithDeviceID(r.Context(), request.DeviceID), input)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, 200, operation)
}

func (a *API) oauthIdentities(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	providers, err := a.auth.LinkedProviders(r.Context(), user.ID)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"providers": providers})
}

func (a *API) linkOAuthIdentity(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	if !a.allowOAuth(w, r) {
		return
	}
	var proof oauthProof
	if err := decodeBody(w, r, 20<<10, &proof); err != nil {
		writeDecodeError(w, err)
		return
	}
	subject, err := a.verifyOAuth(r, proof)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	if err = a.auth.LinkOAuthIdentity(r.Context(), user.ID, proof.Provider, subject, proof.Nonce); err != nil {
		a.writeServiceError(w, err)
		return
	}
	a.oauthIdentities(w, r, user, "")
}
