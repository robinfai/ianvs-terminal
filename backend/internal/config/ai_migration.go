package config

import (
	"bytes"
	"encoding/json"
	"errors"
)

// Read predecessor fields only at the file boundary. Runtime policy and writes
// use Users exclusively; explicit current policy (including zero) wins.
func (g *AIGateway) UnmarshalJSON(data []byte) error {
	type current AIGateway
	var wire struct {
		current
		Quotas   map[string]int64 `json:"user_daily_quota_points"`
		Requests map[string]int   `json:"user_daily_requests"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&wire); err != nil {
		return err
	}
	if wire.Users == nil {
		wire.Users = map[string]AIUserPolicy{}
	}
	for id, value := range wire.Quotas {
		if id == "" || value < 0 || value > 1000000000 {
			return errors.New("invalid predecessor AI quota")
		}
		p := wire.Users[id]
		if p.DailyBudgetNanoUSD == nil {
			budget := value * 2000
			p.DailyBudgetNanoUSD = &budget
		}
		wire.Users[id] = p
	}
	for id, value := range wire.Requests {
		if id == "" || value < 0 || value > 1000000 {
			return errors.New("invalid predecessor AI request quota")
		}
		p := wire.Users[id]
		if p.DailyRequests == nil {
			q := value
			p.DailyRequests = &q
		}
		wire.Users[id] = p
	}
	*g = AIGateway(wire.current)
	return nil
}
