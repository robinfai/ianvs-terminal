package config

import (
	"errors"
	"net/url"
	"slices"
)

// AppleWeb contains public identifiers only. Identity tokens are verified by
// the existing Apple verifier; no signing key is exposed to the browser.
type AppleWeb struct {
	ClientID    string `json:"client_id"`
	RedirectURI string `json:"redirect_uri"`
}

func (p *AppleWeb) Validate(mode Mode, allowed []string) error {
	if p == nil {
		return nil
	}
	u, err := url.Parse(p.RedirectURI)
	if mode != ModeRemote || !slices.Contains(allowed, p.ClientID) || p.ClientID == "" || err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.Fragment != "" || u.RawQuery != "" {
		return errors.New("apple_web requires remote mode, an allowed client_id and an HTTPS redirect_uri without credentials, query or fragment")
	}
	return nil
}
