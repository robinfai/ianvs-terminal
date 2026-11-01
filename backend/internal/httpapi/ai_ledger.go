package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

// A durable per-request record contains pricing/usage only, never prompts or secrets.
type aiLedgerEntry struct {
	ProviderID    string         `json:"provider_id,omitempty"`
	PaidReserved  int64          `json:"purchased_reserved_nano_usd,omitempty"`
	PaidSpent     int64          `json:"purchased_spent_nano_usd,omitempty"`
	ID            string         `json:"id"`
	BudgetKey     string         `json:"budget_key,omitempty"`
	Model         string         `json:"model"`
	Provider      string         `json:"provider"`
	UpstreamModel string         `json:"upstream_model"`
	Price         config.AIPrice `json:"pricing_snapshot"`
	Reserved      int64          `json:"reserved_nano_usd"`
	Status        string         `json:"status"`
	Usage         aiAccount      `json:"usage"`
	CreatedAt     time.Time      `json:"created_at"`
	SettledAt     *time.Time     `json:"settled_at,omitempty"`
}

func aiLedgerPrefix(user string) string { return "ai.ledger." + user + "." }
func aiNewRequestID() (string, error) {
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", err
	}
	return fmt.Sprintf("%016x%s", time.Now().UnixNano(), hex.EncodeToString(random[:])), nil
}

// The upsert obtains a write lock before reading the account, including on SQLite.
// Account and request record commit together; no partial charge can be observed.
func lockedAIAccount(db *gorm.DB, key string, change func(*aiAccount) error) error {
	row := model.Setting{Key: key, Value: "{}"}
	if err := db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error; err != nil {
		return err
	}
	if err := db.Clauses(clause.Locking{Strength: "UPDATE"}).Where("`key` = ?", key).First(&row).Error; err != nil {
		return err
	}
	var account aiAccount
	if err := json.Unmarshal([]byte(row.Value), &account); err != nil {
		return err
	}
	if err := change(&account); err != nil {
		return err
	}
	value, err := json.Marshal(account)
	if err != nil {
		return err
	}
	return db.Model(&model.Setting{}).Where("`key` = ?", key).Updates(map[string]any{"value": string(value), "updated_at": time.Now().UTC()}).Error
}
func (a *API) reserveAISpend(ctx context.Context, user, alias string, m config.AIModel, reserved int64) (aiLedgerEntry, error) {
	id, err := aiNewRequestID()
	if err != nil {
		return aiLedgerEntry{}, err
	}
	entry := aiLedgerEntry{ID: id, BudgetKey: aiAccountKey(user), Model: alias, ProviderID: m.ProviderID, Provider: m.Provider, UpstreamModel: m.Model, Price: m.Pricing, Reserved: reserved, Status: "pending", CreatedAt: time.Now().UTC()}
	err = a.store.DB().WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lockedAIWallet(tx, user, func(wallet *aiWallet) error {
			return lockedAIAccount(tx, entry.BudgetKey, func(account *aiAccount) error {
				free := max(int64(0), a.aiBudget(user)-(account.Spent-account.PaidSpent)-(account.Reserved-account.PaidReserved))
				paid := max(int64(0), reserved-free)
				if reserved <= 0 || a.cfg.AIGateway.Users[user].Disabled || paid > wallet.Balance-wallet.Reserved {
					return errAIBudget
				}
				entry.PaidReserved = paid
				wallet.Reserved += paid
				account.PaidReserved += paid
				account.Reserved += reserved
				account.Pending++
				return nil
			})
		}); err != nil {
			return err
		}
		value, _ := json.Marshal(entry)
		return tx.Create(&model.Setting{Key: aiLedgerPrefix(user) + id, Value: string(value)}).Error
	})
	return entry, err
}
func (a *API) settleAISpend(ctx context.Context, user, id string, actual aiAccount, status string) error {
	if status != "settled" && status != "refunded" {
		return errors.New("invalid AI settlement status")
	}
	return a.store.DB().WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		key := aiLedgerPrefix(user) + id
		// Acquire SQLite's writer lock before selecting; MySQL locks this record.
		if err := tx.Model(&model.Setting{}).Where("`key` = ?", key).UpdateColumn("updated_at", gorm.Expr("updated_at")).Error; err != nil {
			return err
		}
		var row model.Setting
		if err := tx.Where("`key` = ?", key).First(&row).Error; err != nil {
			return err
		}
		var entry aiLedgerEntry
		if err := json.Unmarshal([]byte(row.Value), &entry); err != nil {
			return err
		}
		if entry.Status != "pending" {
			return nil
		} // Idempotent settlement, including after restart.
		if actual.Spent < 0 || (status == "refunded" && actual.Spent != 0) {
			return errors.New("invalid settlement amount")
		}
		if err := lockedAIWallet(tx, user, func(wallet *aiWallet) error {
			return lockedAIAccount(tx, entry.BudgetKey, func(account *aiAccount) error {
				if account.Reserved < entry.Reserved || account.PaidReserved < entry.PaidReserved || wallet.Reserved < entry.PaidReserved || account.Pending < 1 {
					return errors.New("inconsistent AI reservation")
				}
				// Preserve the original day's reservation across midnight. Actual
				// spend may exceed an estimate; record debt rather than lose charges.
				paid := int64(0)
				if entry.PaidReserved > 0 {
					paid = max(int64(0), actual.Spent-(entry.Reserved-entry.PaidReserved))
				}
				wallet.Reserved -= entry.PaidReserved
				wallet.Balance -= paid
				wallet.Spent += paid
				entry.PaidSpent = paid
				account.PaidReserved -= entry.PaidReserved
				account.PaidSpent += paid
				account.Reserved -= entry.Reserved
				account.Pending--
				account.Spent += actual.Spent
				account.Input += actual.Input
				account.Cached += actual.Cached
				account.Output += actual.Output
				if status == "settled" {
					account.Settled++
				}
				return nil
			})
		}); err != nil {
			return err
		}
		now := time.Now().UTC()
		entry.Status = status
		entry.Usage = actual
		entry.SettledAt = &now
		value, _ := json.Marshal(entry)
		return tx.Model(&model.Setting{}).Where("`key` = ?", key).Updates(map[string]any{"value": string(value), "updated_at": now}).Error
	})
}
func (a *API) aiLedger(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	prefix := aiLedgerPrefix(user.ID)
	upper := prefix + "~"
	if cursor := r.URL.Query().Get("before"); cursor != "" {
		if len(cursor) != 48 {
			writeError(w, 400, "invalid_cursor", "Invalid ledger cursor")
			return
		}
		if _, err := hex.DecodeString(cursor); err != nil {
			writeError(w, 400, "invalid_cursor", "Invalid ledger cursor")
			return
		}
		upper = prefix + cursor
	}
	var rows []model.Setting
	if err := a.store.DB().WithContext(r.Context()).Where("`key` >= ? AND `key` < ?", prefix, upper).Order("`key` DESC").Limit(51).Find(&rows).Error; err != nil {
		writeError(w, 503, "quota_unavailable", "Could not load AI ledger")
		return
	}
	more := len(rows) > 50
	if more {
		rows = rows[:50]
	}
	entries := make([]aiLedgerEntry, 0, len(rows))
	for _, row := range rows {
		var entry aiLedgerEntry
		if json.Unmarshal([]byte(row.Value), &entry) != nil {
			writeError(w, 503, "quota_unavailable", "Invalid AI ledger record")
			return
		}
		entry.BudgetKey = ""
		entries = append(entries, entry)
	}
	var next string
	if more {
		next = entries[len(entries)-1].ID
	}
	writeJSON(w, 200, map[string]any{"data": entries, "next_cursor": next})
}
