package config

import "testing"

func TestValidateAIProxy(t *testing.T) {
	for _, address := range []string{"", "http://127.0.0.1:3128", "https://proxy.example.com", "http://[::1]:8080/"} {
		if err := ValidateAIProxy(address, "", ""); err != nil {
			t.Errorf("valid %q: %v", address, err)
		}
	}
	for _, address := range []string{"socks5://proxy:1080", "http://user:secret@proxy:3128", "http://proxy/path", "http://proxy?token=secret", "http://proxy#fragment", "http://", "http://proxy:99999"} {
		if ValidateAIProxy(address, "", "") == nil {
			t.Errorf("invalid accepted %q", address)
		}
	}
	if ValidateAIProxy("", "user", "secret") == nil || ValidateAIProxy("http://proxy", "", "secret") == nil {
		t.Fatal("orphan credential accepted")
	}
}
