package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

type aiWallet struct {
	Balance  int64 `json:"balance_nano_usd"`
	Reserved int64 `json:"reserved_nano_usd"`
	Spent    int64 `json:"spent_nano_usd"`
}

func aiWalletKey(user string) string { return "ai.wallet." + user }
func lockedAIWallet(db *gorm.DB, user string, change func(*aiWallet) error) error {
	row := model.Setting{Key: aiWalletKey(user), Value: "{}"}
	if err := db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error; err != nil {
		return err
	}
	if err := db.Clauses(clause.Locking{Strength: "UPDATE"}).Where("`key` = ?", row.Key).First(&row).Error; err != nil {
		return err
	}
	var wallet aiWallet
	if err := json.Unmarshal([]byte(row.Value), &wallet); err != nil {
		return err
	}
	if err := change(&wallet); err != nil {
		return err
	}
	value, err := json.Marshal(wallet)
	if err != nil {
		return err
	}
	return db.Model(&model.Setting{}).Where("`key` = ?", row.Key).Updates(map[string]any{"value": string(value), "updated_at": time.Now().UTC()}).Error
}
func (a *API) readAIWallet(ctx context.Context, user string) (aiWallet, error) {
	var row model.Setting
	err := a.store.DB().WithContext(ctx).Where("`key` = ?", aiWalletKey(user)).First(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return aiWallet{}, nil
	}
	if err != nil {
		return aiWallet{}, err
	}
	var wallet aiWallet
	err = json.Unmarshal([]byte(row.Value), &wallet)
	return wallet, err
}
func (a *API) purchasesConfig() *config.ApplePurchases {
	if a.cfg.AIGateway == nil {
		return nil
	}
	return a.cfg.AIGateway.ApplePurchases
}

// Opaque, stable UUID scoped to this backend account and bundle. Never use an
// email or a client-chosen account token to assign credit.
func appleAccountToken(user, bundle string) string {
	sum := sha256.Sum256([]byte("trail.apple-purchases.v1\x00" + bundle + "\x00" + user))
	b := sum[:16]
	b[6] = (b[6] & 0x0f) | 0x50
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
}
func (a *API) aiPurchaseProducts(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	p := a.purchasesConfig()
	if p == nil {
		writeJSON(w, 200, map[string]any{"enabled": false, "products": []any{}})
		return
	}
	if a.cfg.AIGateway.Users[user.ID].Disabled {
		writeError(w, 403, "purchase_disabled", "AI access is disabled for this account")
		return
	}
	ids := make([]string, 0, len(p.Products))
	for id := range p.Products {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	products := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		products = append(products, map[string]any{"id": id, "quota_points": p.Products[id]})
	}
	writeJSON(w, 200, map[string]any{"enabled": true, "app_account_token": appleAccountToken(user.ID, p.BundleID), "products": products})
}

type aiPurchase struct {
	TransactionID string    `json:"transaction_id"`
	User          string    `json:"user_id"`
	Product       string    `json:"product_id"`
	Credit        int64     `json:"credit_nano_usd"`
	Environment   string    `json:"environment"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
}

var errPurchaseOwner = errors.New("purchase belongs to another account")
var errPurchaseInvalid = errors.New("invalid purchase")

func purchaseKey(environment, id string) string { return "ai.purchase.apple." + environment + "." + id }

// Only server-fetched Apple transactions reach this method. Receipt and wallet
// commit atomically; a duplicate delivery can never mint additional credit.
func (a *API) creditApplePurchase(ctx context.Context, user string, t appleTransaction) (aiPurchase, error) {
	p := a.purchasesConfig()
	if p == nil || t.BundleID != p.BundleID || t.Environment != p.Environment || t.Type != "Consumable" || t.Quantity != 1 || !validAppleTransactionID(t.ID) || t.PurchaseDate <= 0 || t.PurchaseDate > time.Now().Add(5*time.Minute).UnixMilli() {
		return aiPurchase{}, errPurchaseInvalid
	}
	if !strings.EqualFold(t.AccountToken, appleAccountToken(user, p.BundleID)) {
		return aiPurchase{}, errPurchaseOwner
	}
	var result aiPurchase
	err := a.store.DB().WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return lockedAIWallet(tx, user, func(wallet *aiWallet) error {
			key := purchaseKey(t.Environment, t.ID)
			var row model.Setting
			err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("`key` = ?", key).First(&row).Error
			if err == nil {
				if err = json.Unmarshal([]byte(row.Value), &result); err != nil {
					return err
				}
				if result.User != user || result.Product != t.ProductID {
					return errPurchaseOwner
				}
				if t.RevocationDate != 0 && result.Status == "credited" {
					wallet.Balance -= result.Credit
					result.Status = "revoked"
					return saveAIPurchase(tx, result, false)
				}
				return nil
			}
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				return err
			}
			points, ok := p.Products[t.ProductID]
			if !ok || points <= 0 || points > 1000000000 || t.RevocationDate != 0 {
				return errPurchaseInvalid
			}
			credit := points * 2000
			if wallet.Balance > 1000000000000000-credit {
				return errors.New("wallet limit reached")
			}
			result = aiPurchase{TransactionID: t.ID, User: user, Product: t.ProductID, Credit: credit, Environment: t.Environment, Status: "credited", CreatedAt: time.Now().UTC()}
			wallet.Balance += credit
			return saveAIPurchase(tx, result, true)
		})
	})
	return result, err
}
func (a *API) aiPurchaseVerify(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	p := a.purchasesConfig()
	if p == nil {
		writeError(w, 503, "purchase_unavailable", "Purchases are not configured")
		return
	}
	if a.purchaseLimiter != nil {
		if allowed, _ := a.purchaseLimiter.allow(r.RemoteAddr); !allowed {
			w.Header().Set("Retry-After", "60")
			writeError(w, 429, "rate_limited", "Retry later")
			return
		}
	}
	var body struct {
		TransactionID string `json:"transaction_id"`
	}
	if decodeBody(w, r, 1024, &body) != nil || !validAppleTransactionID(body.TransactionID) {
		writeError(w, 400, "invalid_purchase", "Invalid transaction ID")
		return
	}
	transaction, err := fetchAppleTransaction(r.Context(), p, body.TransactionID)
	if err != nil {
		writeError(w, 503, "purchase_verification_pending", "Could not verify with App Store; retry delivery")
		return
	}
	purchase, err := a.creditApplePurchase(r.Context(), user.ID, transaction)
	if errors.Is(err, errPurchaseOwner) {
		writeError(w, 403, "purchase_account_mismatch", "Sign in to the account used for this purchase")
		return
	}
	if errors.Is(err, errPurchaseInvalid) {
		writeError(w, 400, "invalid_purchase", "Purchase is not eligible for credit")
		return
	}
	if err != nil {
		writeError(w, 503, "purchase_verification_pending", "Purchase delivery pending; retry")
		return
	}
	writeJSON(w, 200, map[string]any{"purchase": purchase})
}
func (a *API) aiPurchases(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	p := a.purchasesConfig()
	if p == nil {
		writeJSON(w, 200, map[string]any{"data": []any{}})
		return
	}
	prefix := "ai.purchase.user." + user.ID + "." + p.Environment + "."
	// User-scoped index bounds the query and keeps account histories isolated.
	var rows []model.Setting
	if err := a.store.DB().WithContext(r.Context()).Where("`key` >= ? AND `key` < ?", prefix, prefix+"~").Order("updated_at DESC").Limit(50).Find(&rows).Error; err != nil {
		writeError(w, 503, "purchase_unavailable", "Could not load purchases")
		return
	}
	result := []aiPurchase{}
	for _, row := range rows {
		var item aiPurchase
		if json.Unmarshal([]byte(row.Value), &item) != nil {
			continue
		}
		if item.User == user.ID {
			item.User = ""
			result = append(result, item)
			if len(result) == 50 {
				break
			}
		}
	}
	writeJSON(w, 200, map[string]any{"data": result})
}

// Notifications are wake-up hints only. No unverified notification fields can
// grant or revoke credit: the server re-fetches the known transaction from Apple.
func (a *API) applePurchaseNotification(w http.ResponseWriter, r *http.Request) {
	p := a.purchasesConfig()
	if p == nil {
		writeError(w, 503, "purchase_unavailable", "Purchases are not configured")
		return
	}
	if allowed, _ := a.purchaseLimiter.allow(r.RemoteAddr); !allowed {
		w.Header().Set("Retry-After", "60")
		writeError(w, 429, "rate_limited", "Retry later")
		return
	}
	var body struct {
		SignedPayload string `json:"signedPayload"`
	}
	if decodeBody(w, r, 65536, &body) != nil {
		writeError(w, 400, "invalid_notification", "Invalid notification")
		return
	}
	var notification struct {
		Data struct {
			SignedTransactionInfo string `json:"signedTransactionInfo"`
		} `json:"data"`
	}
	if decodeAppleHint(body.SignedPayload, &notification) != nil {
		writeError(w, 400, "invalid_notification", "Invalid notification")
		return
	}
	if notification.Data.SignedTransactionInfo == "" {
		writeJSON(w, 200, map[string]any{"received": true})
		return
	}
	var hint struct {
		ID string `json:"transactionId"`
	}
	if decodeAppleHint(notification.Data.SignedTransactionInfo, &hint) != nil || !validAppleTransactionID(hint.ID) {
		writeError(w, 400, "invalid_notification", "Invalid transaction hint")
		return
	}
	var row model.Setting
	err := a.store.DB().WithContext(r.Context()).Where("`key` = ?", purchaseKey(p.Environment, hint.ID)).First(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		writeJSON(w, 200, map[string]any{"received": true})
		return
	}
	var purchase aiPurchase
	if err != nil || json.Unmarshal([]byte(row.Value), &purchase) != nil {
		writeError(w, 503, "purchase_unavailable", "Retry notification")
		return
	}
	transaction, err := fetchAppleTransaction(r.Context(), p, hint.ID)
	if err == nil {
		_, err = a.creditApplePurchase(r.Context(), purchase.User, transaction)
	}
	if err != nil {
		writeError(w, 503, "purchase_verification_pending", "Retry notification")
		return
	}
	writeJSON(w, 200, map[string]any{"received": true})
}

func saveAIPurchase(tx *gorm.DB, p aiPurchase, create bool) error {
	value, err := json.Marshal(p)
	if err != nil {
		return err
	}
	for _, key := range []string{purchaseKey(p.Environment, p.TransactionID), "ai.purchase.user." + p.User + "." + p.Environment + "." + p.TransactionID} {
		row := model.Setting{Key: key, Value: string(value)}
		if create && key == purchaseKey(p.Environment, p.TransactionID) {
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			continue
		}
		if err := tx.Clauses(clause.OnConflict{Columns: []clause.Column{{Name: "key"}}, DoUpdates: clause.Assignments(map[string]any{"value": string(value), "updated_at": time.Now().UTC()})}).Create(&row).Error; err != nil {
			return err
		}
	}
	return nil
}
