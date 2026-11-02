package httpapi

import (
	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"net/http"
)

func (a *API) allowAppleAuth(w http.ResponseWriter, r *http.Request) bool {
	if a.cfg.Mode != config.ModeRemote || len(a.cfg.AppleClientIDs) == 0 {
		writeError(w, http.StatusNotFound, "apple_unavailable", "Apple sign-in is not enabled on this server")
		return false
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "Apple sign-in requires HTTPS")
		return false
	}
	return a.allowAnonymousAuthRequest(w, r)
}
func (a *API) appleChallenge(w http.ResponseWriter, r *http.Request) {
	if !a.allowAppleAuth(w, r) {
		return
	}
	nonce, err := a.auth.CreateAppleChallenge(r.Context())
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"nonce": nonce})
}
func (a *API) beginAppleLogin(w http.ResponseWriter, r *http.Request) {
	if !a.allowAppleAuth(w, r) {
		return
	}
	var request struct {
		IdentityToken string `json:"identity_token"`
		Action        string `json:"action"`
		DeviceID      string `json:"device_id"`
		ReplaceOldest bool   `json:"replace_oldest"`
		Nonce         string `json:"nonce"`
		Username      string `json:"username"`
		Password      string `json:"password"`
	}
	if err := decodeBody(w, r, 20<<10, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	subject, err := a.appleVerifier.Verify(r.Context(), request.IdentityToken, request.Nonce, a.cfg.AppleClientIDs)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	action := request.Action
	if request.Username != "" {
		action = "link"
	}
	operation, err := a.auth.BeginOAuthLogin(auth.WithDeviceID(r.Context(), request.DeviceID), auth.OAuthLogin{Provider: "apple", Subject: subject, Nonce: request.Nonce, Username: request.Username, Password: request.Password, Action: action, AllowRegistration: a.cfg.AllowRegistration, ReplaceOldest: request.ReplaceOldest})
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, operation)
}
