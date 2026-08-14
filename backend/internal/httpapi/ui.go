package httpapi

import (
	"io/fs"
	"mime"
	"net/http"
	"path"
	"strings"

	"ianvs-terminal/backend/webui"
)

// uiFileSystem is rooted at the embedded console build. A nil value (never the
// case for a compiled binary) makes every UI route return 404 while leaving the
// JSON API fully functional.
var uiFileSystem, _ = webui.Sub()

// isWebUIRequest reports whether the request should be served by the embedded
// console rather than the JSON API. Only idempotent reads are routed here, and
// every API path is deliberately excluded so the console can never shadow a
// data endpoint.
func isWebUIRequest(r *http.Request) bool {
	if r.Method != http.MethodGet {
		return false
	}
	p := r.URL.Path
	if p == "/healthz" || strings.HasPrefix(p, "/healthz/") ||
		p == "/v1" || strings.HasPrefix(p, "/v1/") {
		return false
	}
	return true
}

// serveWebUI serves an embedded static asset or, for unknown paths, the SPA
// shell so client-side navigation and deep links keep working.
func (a *API) serveWebUI(w http.ResponseWriter, r *http.Request) {
	if uiFileSystem == nil {
		http.NotFound(w, r)
		return
	}
	requestPath := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if requestPath == "" || requestPath == "." {
		requestPath = "index.html"
	}
	if info, err := fs.Stat(uiFileSystem, requestPath); err == nil && !info.IsDir() {
		serveWebUIFile(w, requestPath)
		return
	}
	index, err := fs.ReadFile(uiFileSystem, "index.html")
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(index)
}

func serveWebUIFile(w http.ResponseWriter, name string) {
	content, err := fs.ReadFile(uiFileSystem, name)
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	contentType := mime.TypeByExtension(path.Ext(name))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	w.Header().Set("Content-Type", contentType)
	if strings.HasPrefix(name, "assets/") {
		// Vite filenames are content-hashed, so they are safe to cache forever.
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		w.Header().Set("Cache-Control", "no-store")
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(content)
}
