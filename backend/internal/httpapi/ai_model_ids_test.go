package httpapi

import (
	"ianvs-terminal/backend/internal/config"
	"testing"
)

func TestPublicAIModelIDs(t *testing.T) {
	g := &config.AIGateway{Models: map[string]config.AIModel{"deepseek": {Model: "deepseek-flash"}, "openai": {Model: "gpt-6.1-sol"}}}
	if publicAIModelID(g, "deepseek") != "deepseek-flash" || publicAIModelID(g, "openai") != "gpt-6.1-sol" {
		t.Fatal("provider aliases exposed")
	}
	g.Models["backup"] = config.AIModel{Model: "deepseek-flash"}
	if publicAIModelID(g, "deepseek") != "deepseek-flash@deepseek" || publicAIModelID(g, "backup") != "deepseek-flash@backup" {
		t.Fatal("duplicate routes ambiguous")
	}
}
