package auth

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

var ErrAppleIdentity = errors.New("Apple identity verification failed")

// AppleTokenVerifier only trusts Apple's fixed HTTPS JWKS endpoint, never a URL
// supplied by the client or a JWT header. Keys are cached to bound network work.
type AppleTokenVerifier struct {
	mu      sync.Mutex
	keys    map[string]*rsa.PublicKey
	fetched time.Time
	client  *http.Client
	jwksURL string
	issuer  string
}

func NewAppleTokenVerifier() *AppleTokenVerifier {
	return &AppleTokenVerifier{client: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}
func NewGoogleTokenVerifier() *AppleTokenVerifier {
	v := NewAppleTokenVerifier()
	v.jwksURL = "https://www.googleapis.com/oauth2/v3/certs"
	v.issuer = "https://accounts.google.com"
	return v
}
func (v *AppleTokenVerifier) publicKeys(ctx context.Context) (map[string]*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.keys != nil && time.Since(v.fetched) < 5*time.Minute {
		return v.keys, nil
	}
	endpoint := v.jwksURL
	if endpoint == "" {
		endpoint = "https://appleid.apple.com/auth/keys"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	res, err := v.client.Do(req)
	if err != nil {
		return nil, ErrAppleIdentity
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, ErrAppleIdentity
	}
	var jwks struct {
		Keys []struct{ Kid, Kty, Alg, Use, N, E string }
	}
	if json.NewDecoder(io.LimitReader(res.Body, 64<<10)).Decode(&jwks) != nil {
		return nil, ErrAppleIdentity
	}
	keys := map[string]*rsa.PublicKey{}
	for _, j := range jwks.Keys {
		if j.Kty != "RSA" || j.Alg != "RS256" || j.Use != "sig" {
			continue
		}
		n, en := base64.RawURLEncoding.DecodeString(j.N)
		e, ee := base64.RawURLEncoding.DecodeString(j.E)
		if en != nil || ee != nil || len(n) < 256 || len(e) == 0 || len(e) > 4 {
			continue
		}
		exponent := 0
		for _, b := range e {
			exponent = exponent*256 + int(b)
		}
		if exponent < 3 || exponent%2 == 0 {
			continue
		}
		keys[j.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: exponent}
	}
	if len(keys) == 0 {
		return nil, ErrAppleIdentity
	}
	v.keys = keys
	v.fetched = time.Now()
	return keys, nil
}
func (v *AppleTokenVerifier) Verify(ctx context.Context, token, nonce string, audiences []string) (string, error) {
	if len(token) > 16384 || len(nonce) != 43 || len(audiences) == 0 {
		return "", ErrAppleIdentity
	}
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", ErrAppleIdentity
	}
	var header struct{ Alg, Kid string }
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || json.Unmarshal(raw, &header) != nil || header.Alg != "RS256" || header.Kid == "" {
		return "", ErrAppleIdentity
	}
	keys, err := v.publicKeys(ctx)
	if err != nil {
		return "", err
	}
	key := keys[header.Kid]
	if key == nil {
		return "", ErrAppleIdentity
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return "", ErrAppleIdentity
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig) != nil {
		return "", ErrAppleIdentity
	}
	var claims struct {
		Iss, Aud, Sub, Nonce string
		Exp, Iat             int64
	}
	raw, err = base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || json.Unmarshal(raw, &claims) != nil {
		return "", ErrAppleIdentity
	}
	accepted := false
	for _, aud := range audiences {
		if claims.Aud == aud {
			accepted = true
		}
	}
	now := time.Now().Unix()
	issuer := v.issuer
	if issuer == "" {
		issuer = "https://appleid.apple.com"
	}
	validIssuer := claims.Iss == issuer || (issuer == "https://accounts.google.com" && claims.Iss == "accounts.google.com")
	if !accepted || !validIssuer || claims.Nonce != nonce || claims.Exp <= now || claims.Iat > now+60 || claims.Iat < now-600 || len(claims.Sub) == 0 || len(claims.Sub) > 255 {
		return "", ErrAppleIdentity
	}
	return claims.Sub, nil
}
