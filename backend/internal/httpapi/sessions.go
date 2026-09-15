package httpapi

import (
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
	"net/http"
)

func (a *API) listSessions(w http.ResponseWriter, r *http.Request, user model.User, token string) {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, http.StatusNotFound, "not_found", "sessions are unavailable in local mode")
		return
	}
	sessions, err := a.auth.ListSessions(r.Context(), user.ID, token)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"sessions": sessions})
}
func (a *API) revokeSession(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, http.StatusNotFound, "not_found", "sessions are unavailable in local mode")
		return
	}
	if err := a.auth.RevokeSession(r.Context(), user.ID, r.PathValue("id")); err != nil {
		a.writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func deviceLabel(name, userAgent string) string {
	if name != "" {
		return name
	}
	return userAgent
}
