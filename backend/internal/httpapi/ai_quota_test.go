package httpapi

import (
	"ianvs-terminal/backend/internal/config"
	"testing"
)

func TestAIUsageCost(t *testing.T) {
	price := config.AIPrice{Input: 300, CachedInput: 6, Output: 1200}
	for _, tt := range []struct {
		name, raw string
		want      int64
		ok        bool
	}{
		{"uncached", `{"usage":{"prompt_tokens":10000,"completion_tokens":2000}}`, 5400000, true},
		{"deepseek cache", `{"usage":{"prompt_tokens":10000,"completion_tokens":2000,"prompt_cache_hit_tokens":8000}}`, 3048000, true},
		{"openai cache", `{"usage":{"prompt_tokens":10000,"completion_tokens":2000,"prompt_tokens_details":{"cached_tokens":8000},"completion_tokens_details":{"reasoning_tokens":1000}}}`, 3048000, true},
		{"zero", `{"usage":{"prompt_tokens":0,"completion_tokens":0}}`, 0, true},
		{"missing", `{"usage":null}`, 0, false},
		{"partial", `{"usage":{"prompt_tokens":100}}`, 0, false},
		{"invalid", `{"usage":{"prompt_tokens":100,"completion_tokens":-1}}`, 0, false},
		{"cache exceeds input", `{"usage":{"prompt_tokens":100,"completion_tokens":1,"prompt_cache_hit_tokens":101}}`, 0, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := aiUsageCost([]byte(tt.raw), price)
			if ok != tt.ok || got.Spent != tt.want {
				t.Fatalf("%+v %v", got, ok)
			}
		})
	}
}
