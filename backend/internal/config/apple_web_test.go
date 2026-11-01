package config

import "testing"

func TestAppleWebConfiguration(t *testing.T) {
	for _, tc := range []struct {
		name, id, uri string
		mode          Mode
		ok            bool
	}{
		{"valid", "work.ianvs.trail.web", "https://api.terminal.ianvs.work/", ModeRemote, true},
		{"untrusted audience", "other", "https://api.terminal.ianvs.work/", ModeRemote, false},
		{"insecure", "work.ianvs.trail.web", "http://example.com/", ModeRemote, false},
		{"credentials", "work.ianvs.trail.web", "https://user@example.com/", ModeRemote, false},
		{"fragment", "work.ianvs.trail.web", "https://example.com/#token", ModeRemote, false},
		{"local", "work.ianvs.trail.web", "https://example.com/", ModeLocal, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := &AppleWeb{ClientID: tc.id, RedirectURI: tc.uri}
			if (p.Validate(tc.mode, []string{"work.ianvs.trail.web"}) == nil) != tc.ok {
				t.Fatal("unexpected validation result")
			}
		})
	}
}
