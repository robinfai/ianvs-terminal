package config

import (
	"errors"
	"net/url"
	"strings"
)

// AIGateway keeps provider credentials and per-user UTC daily budgets server-side.
type AIGateway struct {
	ApplePurchases       *ApplePurchases         `json:"apple_purchases,omitempty"`
	PricingCatalog       map[string]AIPrice      `json:"pricing_catalog,omitempty"`
	BudgetNanoUSD        *int64                  `json:"daily_budget_nano_usd,omitempty"`
	Users                map[string]AIUserPolicy `json:"users,omitempty"`
	DailyQuotaPoints     int64                   `json:"daily_quota_points"`
	UserDailyQuotaPoints map[string]int64        `json:"user_daily_quota_points"`
	DefaultModel         string                  `json:"default_model"`
	DailyRequests        int                     `json:"daily_requests"`
	UserDailyRequests    map[string]int          `json:"user_daily_requests"`
	Models               map[string]AIModel      `json:"models"`
}
type AIModel struct {
	PriceID         string  `json:"price_id,omitempty"`
	Pricing         AIPrice `json:"pricing"`
	Provider        string  `json:"provider"`
	Endpoint        string  `json:"endpoint"`
	APIKey          string  `json:"api_key"`
	Model           string  `json:"model"`
	MaxOutputTokens int     `json:"max_output_tokens"`
}

func (g *AIGateway) Validate() error {
	if g == nil {
		return nil
	}
	if err := g.ApplePurchases.Validate(); err != nil {
		return err
	}
	if g.BudgetNanoUSD != nil && (*g.BudgetNanoUSD < 0 || *g.BudgetNanoUSD > 2000000000000) {
		return errors.New("invalid default AI money budget")
	}
	for user, policy := range g.Users {
		if user == "" || (policy.DailyBudgetNanoUSD != nil && (*policy.DailyBudgetNanoUSD < 0 || *policy.DailyBudgetNanoUSD > 2000000000000)) || (policy.DailyRequests != nil && *policy.DailyRequests < 0) {
			return errors.New("invalid AI user policy")
		}
		for _, alias := range policy.AllowedModels {
			if _, ok := g.Models[alias]; !ok {
				return errors.New("unknown model in AI user policy")
			}
		}
		for alias, price := range policy.PricingOverrides {
			if _, ok := g.Models[alias]; !ok || !price.Valid() {
				return errors.New("invalid AI scoped pricing")
			}
		}
	}
	if g.DailyQuotaPoints < 0 || g.DailyQuotaPoints > 1000000000 {
		return errors.New("invalid AI daily quota points")
	}
	for user, quota := range g.UserDailyQuotaPoints {
		if user == "" || quota < 0 || quota > 1000000000 {
			return errors.New("invalid AI user quota points")
		}
	}
	if g.DailyRequests < 0 || len(g.Models) == 0 {
		return errors.New("ai_gateway requires models and a nonnegative daily quota")
	}
	if _, ok := g.Models[g.DefaultModel]; !ok {
		return errors.New("ai_gateway default_model must reference a configured alias")
	}
	for user, quota := range g.UserDailyRequests {
		if user == "" || quota < 0 {
			return errors.New("invalid AI user quota")
		}
	}
	for id, price := range g.PricingCatalog {
		if id == "" || !price.Valid() || price.Version == "" {
			return errors.New("pricing catalog requires valid versioned prices")
		}
	}
	for alias, m := range g.Models {
		if m.PriceID != "" {
			if _, ok := g.PricingCatalog[m.PriceID]; !ok {
				return errors.New("unknown AI price_id")
			}
			if m.Pricing != (AIPrice{}) {
				return errors.New("use either price_id or inline pricing")
			}
		}
		if !g.ModelPrice(alias).Valid() {
			return errors.New("invalid AI model token prices")
		}
		u, err := url.Parse(m.Endpoint)
		if alias == "" || (m.Provider != "openai" && m.Provider != "deepseek") || err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || strings.TrimSpace(m.APIKey) == "" || strings.ContainsAny(m.APIKey, "\r\n") || m.Model == "" || m.MaxOutputTokens < 1 || m.MaxOutputTokens > 32768 {
			return errors.New("invalid ai_gateway model: require openai/deepseek, HTTPS endpoint, credential, model and output token cap (1-32768)")
		}
	}
	return nil
}

// Rates are integer nano-USD per token: $0.30 / million = 300.
// One New API-compatible quota point is 2,000 nano-USD.
type AIPrice struct {
	Version     string `json:"version,omitempty"`
	Input       int64  `json:"input_nano_usd_per_token"`
	CachedInput int64  `json:"cached_input_nano_usd_per_token"`
	Output      int64  `json:"output_nano_usd_per_token"`
}

// User policy is the app's authenticated-user equivalent of a scoped virtual key.
// nil allowed_models inherits all models; [] denies all. Explicit zero daily budget provides no free allowance; purchased credit remains available.
type AIUserPolicy struct {
	Disabled           bool               `json:"disabled,omitempty"`
	DailyBudgetNanoUSD *int64             `json:"daily_budget_nano_usd,omitempty"`
	DailyRequests      *int               `json:"daily_requests,omitempty"`
	AllowedModels      []string           `json:"allowed_models"`
	PricingOverrides   map[string]AIPrice `json:"pricing_overrides,omitempty"`
}

func (p AIPrice) Valid() bool {
	return p.Input > 0 && p.Output > 0 && p.CachedInput >= 0 && p.CachedInput <= p.Input && p.Input <= 1000000 && p.Output <= 1000000 && len(p.Version) <= 128
}
func (g *AIGateway) Allows(user, alias string) bool {
	p := g.Users[user]
	if p.Disabled {
		return false
	}
	if p.AllowedModels == nil {
		return true
	}
	for _, allowed := range p.AllowedModels {
		if alias == allowed {
			return true
		}
	}
	return false
}
func (g *AIGateway) PriceFor(user, alias string) AIPrice {
	if p, ok := g.Users[user].PricingOverrides[alias]; ok {
		return p
	}
	return g.ModelPrice(alias)
}
func (g *AIGateway) RequestLimit(user string) int {
	if g.Users[user].Disabled {
		return 0
	}
	if q := g.Users[user].DailyRequests; q != nil {
		return *q
	}
	if q, ok := g.UserDailyRequests[user]; ok {
		return q
	}
	return g.DailyRequests
}

func (g *AIGateway) ModelPrice(alias string) AIPrice {
	model := g.Models[alias]
	if model.PriceID != "" {
		return g.PricingCatalog[model.PriceID]
	}
	return model.Pricing
}
