package httpapi

import (
	"ianvs-terminal/backend/internal/config"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestAIRateWindowsAndIsolation(t *testing.T) {
	now := time.Unix(100000, 0)
	for index, window := range []time.Duration{time.Second, time.Minute, time.Hour, time.Minute, time.Hour} {
		l := &aiRateLimiter{users: make(map[string][]*aiRateEvent)}
		limits := [5]int64{100, 100, 100, 10000, 10000}
		limits[index] = 1
		if e, _ := l.reserve("u", limits, 1, now); e == nil {
			t.Fatal("first rejected")
		}
		if e, retry := l.reserve("u", limits, 1, now); e != nil || retry != window {
			t.Fatalf("window %d retry %v", index, retry)
		}
		if e, _ := l.reserve("other", limits, 1, now); e == nil {
			t.Fatal("cross-user interference")
		}
		if e, _ := l.reserve("u", limits, 1, now.Add(window)); e == nil {
			t.Fatalf("boundary %d", index)
		}
	}
}
func TestAIRateAtomicReservationSettlementAndPolicyChange(t *testing.T) {
	now := time.Unix(100000, 0)
	l := &aiRateLimiter{users: make(map[string][]*aiRateEvent)}
	limits := config.AIUserPolicy{}.RateLimits()
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 40; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if e, _ := l.reserve("u", limits, 8000, now); e != nil {
				accepted.Add(1)
			}
		}()
	}
	wg.Wait()
	if accepted.Load() != 1 {
		t.Fatalf("accepted %d", accepted.Load())
	}
	// Raising a policy does not reset history; token reservations block concurrency.
	limits = [5]int64{100, 100, 100, 10000, 10000}
	if e, _ := l.reserve("u", limits, 3000, now); e != nil {
		t.Fatal("token reservation bypass")
	}
	l.settle(l.users["u"][0], 1000)
	if e, _ := l.reserve("u", limits, 3000, now); e == nil {
		t.Fatal("actual usage did not release tokens")
	}
	limits[4] = 3999
	if e, _ := l.reserve("u", limits, 1, now); e != nil {
		t.Fatal("lowered policy reset history")
	}
	if e, _ := l.reserve("u", limits, 1, now.Add(time.Hour)); e == nil {
		t.Fatal("stale usage retained")
	}
}

func TestAIRateStaleUsersCleanedAndRejectedRequestsDoNotCount(t *testing.T) {
	now := time.Unix(100000, 0)
	l := &aiRateLimiter{users: make(map[string][]*aiRateEvent)}
	limits := config.AIUserPolicy{}.RateLimits()
	l.reserve("old", limits, 1, now)
	for i := 0; i < 20; i++ {
		l.reserve("old", limits, 1, now)
	}
	if len(l.users["old"]) != 1 {
		t.Fatal("rejected request extended window")
	}
	l.reserve("new", limits, 1, now.Add(time.Hour))
	if _, ok := l.users["old"]; ok {
		t.Fatal("stale user retained")
	}
}
