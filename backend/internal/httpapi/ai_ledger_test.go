package httpapi

import (
	"context"
	"encoding/json"
	"path/filepath"
	"sync"
	"testing"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

func TestAILedgerAtomicIdempotentSettlement(t *testing.T) {
	ctx := context.Background()
	cfg := config.Config{DatabaseDriver: "sqlite", DatabaseDSN: filepath.Join(t.TempDir(), "ledger.db"), AIGateway: &config.AIGateway{DailyQuotaPoints: 100}}
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, _ := db.DB()
	t.Cleanup(func() { _ = sqlDB.Close() })
	resourceStore, err := store.New(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	api := &API{cfg: cfg, store: resourceStore}
	m := config.AIModel{Provider: "deepseek", Model: "deepseek-flash", Pricing: config.AIPrice{Version: "v1", Input: 300, CachedInput: 6, Output: 1200}}
	if err := db.Create(&model.Setting{Key: aiAccountKey("user-one"), Value: `{"spent_nano_usd":500}`}).Error; err != nil {
		t.Fatal(err)
	}
	entry, err := api.reserveAISpend(ctx, "user-one", "ds", m, 10000)
	if err != nil {
		t.Fatal(err)
	}
	actual := aiAccount{Spent: 1000, Input: 10, Output: 2}
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := api.settleAISpend(ctx, "user-one", entry.ID, actual, "settled"); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	var row model.Setting
	if err := db.Where("`key` = ?", entry.BudgetKey).First(&row).Error; err != nil {
		t.Fatal(err)
	}
	var account aiAccount
	if err := json.Unmarshal([]byte(row.Value), &account); err != nil {
		t.Fatal(err)
	}
	if account.Spent != 1500 || account.Reserved != 0 || account.Pending != 0 || account.Settled != 1 {
		t.Fatalf("double settlement: %+v", account)
	}
	if err := db.Where("`key` = ?", aiLedgerPrefix("user-one")+entry.ID).First(&model.Setting{}).Error; err != nil {
		t.Fatal(err)
	}
	if _, err := api.reserveAISpend(ctx, "user-one", "ds", m, 200000); err != errAIBudget {
		t.Fatalf("overbudget request admitted: %v", err)
	}
	var count int64
	db.Model(&model.Setting{}).Where("`key` LIKE ?", aiLedgerPrefix("user-one")+"%").Count(&count)
	if count != 1 {
		t.Fatalf("rejected reservation wrote ledger: %d", count)
	}
	// Restart/retry uses the persisted status, not an in-memory flag.
	restarted := &API{cfg: cfg, store: resourceStore}
	if err := restarted.settleAISpend(ctx, "user-one", entry.ID, actual, "settled"); err != nil {
		t.Fatal(err)
	}
	if err := restarted.settleAISpend(ctx, "user-two", entry.ID, actual, "settled"); err == nil {
		t.Fatal("cross-user settlement allowed")
	}
}
