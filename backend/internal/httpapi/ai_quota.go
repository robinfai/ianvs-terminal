package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"gorm.io/gorm/clause"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

type aiAccount struct {
	Spent    int64 `json:"spent_nano_usd"`
	Reserved int64 `json:"reserved_nano_usd"`
	Input    int64 `json:"input_tokens"`
	Cached   int64 `json:"cached_input_tokens"`
	Output   int64 `json:"output_tokens"`
	Settled  int64 `json:"settled_requests"`
	Pending  int64 `json:"pending_requests"`
}

func aiAccountKey(user string) string {
	return "ai.budget." + time.Now().UTC().Format("2006-01-02") + "." + user
}
func (a *API) aiBudget(user string) int64 {
	g := a.cfg.AIGateway
	if g.Users[user].Disabled {
		return 0
	}
	if budget := g.Users[user].DailyBudgetNanoUSD; budget != nil {
		return *budget
	}
	if q, ok := g.UserDailyQuotaPoints[user]; ok {
		return q * 2000
	}
	if g.BudgetNanoUSD != nil {
		return *g.BudgetNanoUSD
	}
	return g.DailyQuotaPoints * 2000
}

var errAIBudget = errors.New("AI budget exhausted")

// Atomic compare-and-swap protects both reservations and settlement across replicas.
func (a *API) updateAIAccount(ctx context.Context, key string, change func(*aiAccount) error) (aiAccount, error) {
	db := a.store.DB().WithContext(ctx)
	row := model.Setting{Key: key, Value: "{}"}
	if err := db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error; err != nil {
		return aiAccount{}, err
	}
	for i := 0; i < 64; i++ {
		if err := db.Where("`key` = ?", key).First(&row).Error; err != nil {
			return aiAccount{}, err
		}
		var account aiAccount
		if err := json.Unmarshal([]byte(row.Value), &account); err != nil {
			return account, err
		}
		if err := change(&account); err != nil {
			return account, err
		}
		value, _ := json.Marshal(account)
		result := db.Model(&model.Setting{}).Where("`key` = ? AND value = ?", key, row.Value).Updates(map[string]any{"value": string(value), "updated_at": time.Now().UTC()})
		if result.Error != nil {
			return account, result.Error
		}
		if result.RowsAffected == 1 {
			return account, nil
		}
	}
	return aiAccount{}, errors.New("quota contention")
}
func (a *API) aiUsage(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	if a.cfg.AIGateway == nil {
		writeError(w, 503, "ai_unavailable", "AI gateway is not configured")
		return
	}
	account, err := a.updateAIAccount(r.Context(), aiAccountKey(user.ID), func(*aiAccount) error { return nil })
	if err != nil {
		writeError(w, 503, "quota_unavailable", "Could not read AI quota")
		return
	}
	budget := a.aiBudget(user.ID)
	remaining := budget - account.Spent - account.Reserved
	if remaining < 0 {
		remaining = 0
	}
	writeJSON(w, 200, map[string]any{"usage": account, "daily_budget_nano_usd": budget, "remaining_nano_usd": remaining, "daily_quota_points": float64(budget) / 2000, "remaining_quota_points": float64(remaining) / 2000, "quota_points_per_usd": 500000, "reset_timezone": "UTC", "reset_at": time.Now().UTC().Truncate(24 * time.Hour).Add(24 * time.Hour)})
}

type aiTokenUsage struct {
	Prompt     *int64 `json:"prompt_tokens"`
	Completion *int64 `json:"completion_tokens"`
	CacheHit   *int64 `json:"prompt_cache_hit_tokens"`
	Details    struct {
		Cached int64 `json:"cached_tokens"`
	} `json:"prompt_tokens_details"`
}

func aiUsageCost(raw []byte, price config.AIPrice) (aiAccount, bool) {
	var envelope struct {
		Usage *aiTokenUsage `json:"usage"`
	}
	if json.Unmarshal(raw, &envelope) != nil || envelope.Usage == nil {
		return aiAccount{}, false
	}
	u := envelope.Usage
	if u.Prompt == nil || u.Completion == nil {
		return aiAccount{}, false
	}
	cached := u.Details.Cached
	if u.CacheHit != nil {
		cached = *u.CacheHit
	}
	if *u.Prompt < 0 || *u.Prompt > 2000000 || *u.Completion < 0 || *u.Completion > 2000000 || cached < 0 || cached > *u.Prompt {
		return aiAccount{}, false
	}
	return aiAccount{Input: *u.Prompt, Cached: cached, Output: *u.Completion, Spent: (*u.Prompt-cached)*price.Input + cached*price.CachedInput + *u.Completion*price.Output}, true
}
