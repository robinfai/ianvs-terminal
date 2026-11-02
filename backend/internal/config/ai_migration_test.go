package config

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestAIPredecessorPolicyNormalizedAtDecode(t *testing.T) {
	var g AIGateway
	data := `{"daily_requests":100,"user_daily_quota_points":{"old":5,"current":9},"user_daily_requests":{"old":7,"current":8},"users":{"current":{"daily_budget_nano_usd":0,"daily_requests":0}}}`
	if err := json.Unmarshal([]byte(data), &g); err != nil {
		t.Fatal(err)
	}
	if *g.Users["old"].DailyBudgetNanoUSD != 10000 || g.RequestLimit("old") != 7 || *g.Users["current"].DailyBudgetNanoUSD != 0 || g.RequestLimit("current") != 0 {
		t.Fatal("precedence changed")
	}
	encoded, err := json.Marshal(g)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "user_daily_") {
		t.Fatal("writes predecessor fields")
	}
	var again AIGateway
	if err := json.Unmarshal(encoded, &again); err != nil || again.RequestLimit("old") != 7 {
		t.Fatal("canonical roundtrip failed", err)
	}
}
func TestAIPredecessorDecoderRemainsStrict(t *testing.T) {
	for _, data := range []string{`{"typo":1}`, `{"user_daily_requests":{"u":-1}}`, `{"user_daily_quota_points":{"u":1000000001}}`, `{"users":{"u":{"unknown":1}}}`} {
		var g AIGateway
		if json.Unmarshal([]byte(data), &g) == nil {
			t.Fatal("accepted", data)
		}
	}
}
