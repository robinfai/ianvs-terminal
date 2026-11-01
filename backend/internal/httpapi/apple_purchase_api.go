package httpapi

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"ianvs-terminal/backend/internal/config"
)

type appleTransaction struct {
	ID             string `json:"transactionId"`
	BundleID       string `json:"bundleId"`
	ProductID      string `json:"productId"`
	AccountToken   string `json:"appAccountToken"`
	Environment    string `json:"environment"`
	Type           string `json:"type"`
	Quantity       int    `json:"quantity"`
	PurchaseDate   int64  `json:"purchaseDate"`
	RevocationDate int64  `json:"revocationDate"`
}

func validAppleTransactionID(id string) bool {
	if len(id) < 1 || len(id) > 64 {
		return false
	}
	for _, c := range id {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

var applePurchaseHTTPClient = &http.Client{Timeout: 20 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func appleServerToken(p *config.ApplePurchases) (string, error) {
	data, err := os.ReadFile(p.PrivateKeyFile)
	if err != nil {
		return "", err
	}
	block, _ := pem.Decode(data)
	if block == nil {
		return "", errors.New("invalid Apple private key")
	}
	raw, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", err
	}
	key, ok := raw.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() {
		return "", errors.New("Apple key must be ES256")
	}
	header, _ := json.Marshal(map[string]any{"alg": "ES256", "kid": p.KeyID, "typ": "JWT"})
	now := time.Now().Unix()
	claims, _ := json.Marshal(map[string]any{"iss": p.IssuerID, "iat": now, "exp": now + 300, "aud": "appstoreconnect-v1", "bid": p.BundleID})
	encode := base64.RawURLEncoding.EncodeToString
	input := encode(header) + "." + encode(claims)
	hash := sha256.Sum256([]byte(input))
	r, s, err := ecdsa.Sign(rand.Reader, key, hash[:])
	if err != nil {
		return "", err
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	s.FillBytes(signature[32:])
	return input + "." + encode(signature), nil
}
func fetchAppleTransaction(ctx context.Context, p *config.ApplePurchases, id string) (appleTransaction, error) {
	var transaction appleTransaction
	if !validAppleTransactionID(id) {
		return transaction, errPurchaseInvalid
	}
	token, err := appleServerToken(p)
	if err != nil {
		return transaction, err
	}
	host := "https://api.storekit.apple.com"
	if p.Environment == "Sandbox" {
		host = "https://api.storekit-sandbox.apple.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, host+"/inApps/v1/transactions/"+id, nil)
	if err != nil {
		return transaction, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	response, err := applePurchaseHTTPClient.Do(req)
	if err != nil {
		return transaction, err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return transaction, errors.New("App Store transaction lookup failed")
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 65537))
	if err != nil || len(data) > 65536 {
		return transaction, errors.New("invalid App Store response")
	}
	var envelope struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	}
	if json.Unmarshal(data, &envelope) != nil {
		return transaction, errPurchaseInvalid
	}
	// This JWS is obtained ONLY from Apple's authenticated fixed HTTPS endpoint,
	// never from the client or a notification. TLS authenticates its provenance.
	// Do not reuse this decoder for untrusted client-supplied JWS payloads.
	parts := strings.Split(envelope.SignedTransactionInfo, ".")
	if len(parts) != 3 {
		return transaction, errPurchaseInvalid
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return transaction, err
	}
	if json.Unmarshal(payload, &transaction) != nil || transaction.ID != id {
		return transaction, errPurchaseInvalid
	}
	return transaction, nil
}

// Parses only lookup hints, never purchase evidence. The authenticated Apple
// Server API response is the only authority used for ledger mutations.
func decodeAppleHint(raw string, target any) error {
	parts := strings.Split(raw, ".")
	if len(parts) != 3 {
		return errPurchaseInvalid
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return err
	}
	return json.Unmarshal(payload, target)
}
