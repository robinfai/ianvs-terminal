package config

import (
	"errors"
	"strings"
)

// Product credit is server-owned. Never change the amount of an existing ID.
// Sandbox must use a separate backend/database; production rejects sandbox purchases.
type ApplePurchases struct {
	BundleID       string           `json:"bundle_id"`
	IssuerID       string           `json:"issuer_id"`
	KeyID          string           `json:"key_id"`
	PrivateKeyFile string           `json:"private_key_file"`
	Environment    string           `json:"environment"`
	Products       map[string]int64 `json:"products"` // Product ID -> quota points.
}

func (p *ApplePurchases) Validate() error {
	if p == nil {
		return nil
	}
	if p.BundleID == "" || p.IssuerID == "" || p.KeyID == "" || p.PrivateKeyFile == "" || (p.Environment != "Production" && p.Environment != "Sandbox") || len(p.Products) == 0 || len(p.Products) > 20 {
		return errors.New("apple_purchases requires bundle, issuer, key, private key file, environment and products")
	}
	for id, points := range p.Products {
		if strings.TrimSpace(id) != id || id == "" || len(id) > 200 || points <= 0 || points > 1000000000 {
			return errors.New("invalid Apple quota product")
		}
	}
	return nil
}
