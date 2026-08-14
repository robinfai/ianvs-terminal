// Package webui embeds the compiled Ianvs SSH Profile Vault single-page
// application so the API binary can serve it without external static assets.
package webui

import (
	"embed"
	"io/fs"
)

// Dist holds the production build of the console (index.html plus hashed assets).
//
//go:embed all:dist
var Dist embed.FS

// Sub returns a filesystem rooted at the embedded dist directory. It returns an
// error only when the dist directory is absent, which cannot happen for a
// compiled binary that embeds it.
func Sub() (fs.FS, error) {
	return fs.Sub(Dist, "dist")
}
