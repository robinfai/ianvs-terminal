package httpapi

import (
	"sync"
	"time"
)

type aiRateEvent struct {
	at     time.Time
	tokens int64
}

// Pointer shared by immutable API snapshots. Counters intentionally reset on restart.
type aiRateLimiter struct {
	mu      sync.Mutex
	users   map[string][]*aiRateEvent
	cleanup time.Time
}

func (l *aiRateLimiter) reserve(user string, limits [5]int64, tokens int64, now time.Time) (*aiRateEvent, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if !now.Before(l.cleanup) {
		for id, events := range l.users {
			if len(events) == 0 || !events[len(events)-1].at.After(now.Add(-time.Hour)) {
				delete(l.users, id)
			}
		}
		l.cleanup = now.Add(time.Minute)
	}
	events := l.users[user]
	start := 0
	for start < len(events) && !events[start].at.After(now.Add(-time.Hour)) {
		start++
	}
	if start > 0 {
		events = append([]*aiRateEvent(nil), events[start:]...)
		l.users[user] = events
	}
	if len(events) == 0 && len(l.users) >= 10000 {
		return nil, time.Minute
	}
	windows := [5]time.Duration{time.Second, time.Minute, time.Hour, time.Minute, time.Hour}
	var retry time.Duration
	for i, window := range windows {
		cost := int64(1)
		if i >= 3 {
			cost = tokens
		}
		sum := cost
		for _, e := range events {
			if e.at.After(now.Add(-window)) {
				if i >= 3 {
					sum += e.tokens
				} else {
					sum++
				}
			}
		}
		if sum <= limits[i] {
			continue
		}
		wait := window
		for _, e := range events {
			if !e.at.After(now.Add(-window)) {
				continue
			}
			if i >= 3 {
				sum -= e.tokens
			} else {
				sum--
			}
			if sum <= limits[i] {
				wait = e.at.Add(window).Sub(now)
				break
			}
		}
		if wait > retry {
			retry = wait
		}
	}
	if retry > 0 {
		return nil, retry
	}
	e := &aiRateEvent{at: now, tokens: tokens}
	l.users[user] = append(events, e)
	return e, 0
}
func (l *aiRateLimiter) settle(e *aiRateEvent, tokens int64) {
	l.mu.Lock()
	defer l.mu.Unlock()
	e.tokens = tokens
}
