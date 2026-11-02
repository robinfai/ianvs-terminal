package config

import "testing"

func TestAIPricingCatalogAndUserPolicy(t *testing.T) {
	zero := int64(0)
	base := AIPrice{Version: "2026-11-01", Input: 300, CachedInput: 6, Output: 1200}
	discount := AIPrice{Version: "customer-plan-v1", Input: 150, CachedInput: 3, Output: 600}
	g := &AIGateway{DefaultModel: "ds", PricingCatalog: map[string]AIPrice{"flash": base}, Models: map[string]AIModel{"ds": {PriceID: "flash", Provider: "deepseek", Endpoint: "https://api.deepseek.com/v1", APIKey: "secret", Model: "deepseek-flash", MaxOutputTokens: 4096}}, Users: map[string]AIUserPolicy{
		"disabled": {Disabled: true}, "none": {AllowedModels: []string{}}, "customer": {AllowedModels: []string{"ds"}, DailyBudgetNanoUSD: &zero, PricingOverrides: map[string]AIPrice{"ds": discount}},
	}}
	if err := g.Validate(); err != nil {
		t.Fatal(err)
	}
	if g.Allows("disabled", "ds") || g.Allows("none", "ds") || !g.Allows("new", "ds") || !g.Allows("customer", "ds") {
		t.Fatal("incorrect policy inheritance")
	}
	if g.PriceFor("customer", "ds") != discount || g.PriceFor("new", "ds") != base {
		t.Fatal("incorrect scoped pricing")
	}
	model := g.Models["ds"]
	model.PriceID = "missing"
	g.Models["ds"] = model
	if g.Validate() == nil {
		t.Fatal("unknown catalog reference accepted")
	}
	model.PriceID = "flash"
	model.Pricing = base
	g.Models["ds"] = model
	if g.Validate() == nil {
		t.Fatal("ambiguous inline and catalog pricing accepted")
	}
}

func TestAIRateDefaultsAndOverrides(t *testing.T) {
	if got := (AIUserPolicy{}).RateLimits(); got != [5]int64{1, 10, 100, 100000, 1000000} {
		t.Fatal(got)
	}
	override := 7
	if got := (AIUserPolicy{RequestsPerSecond: &override, TokensPerMinute: &override}).RateLimits(); got != [5]int64{7, 10, 100, 7, 1000000} {
		t.Fatal(got)
	}
}
