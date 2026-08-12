package httpapi

import (
	"math"
	"net"
	"strings"
	"sync"
	"time"
)

const (
	anonymousAuthBurst           = 10
	anonymousAuthTokensPerMinute = 10
	anonymousAuthEntryTTL        = 15 * time.Minute
	anonymousAuthCleanupInterval = time.Minute
	anonymousAuthMaximumPeers    = 4096
)

type peerTokenBucket struct {
	tokens     float64
	lastRefill time.Time
	lastSeen   time.Time
}

type peerRateLimiter struct {
	mu              sync.Mutex
	peers           map[string]*peerTokenBucket
	capacity        float64
	tokensPerSecond float64
	entryTTL        time.Duration
	cleanupInterval time.Duration
	maximumPeers    int
	nextCleanup     time.Time
	now             func() time.Time
}

func newAnonymousAuthRateLimiter() *peerRateLimiter {
	return newPeerRateLimiter(
		anonymousAuthBurst,
		float64(anonymousAuthTokensPerMinute)/60,
		anonymousAuthEntryTTL,
		anonymousAuthCleanupInterval,
		anonymousAuthMaximumPeers,
		time.Now,
	)
}

func newPeerRateLimiter(
	capacity int,
	tokensPerSecond float64,
	entryTTL, cleanupInterval time.Duration,
	maximumPeers int,
	now func() time.Time,
) *peerRateLimiter {
	return &peerRateLimiter{
		peers:           make(map[string]*peerTokenBucket),
		capacity:        float64(capacity),
		tokensPerSecond: tokensPerSecond,
		entryTTL:        entryTTL,
		cleanupInterval: cleanupInterval,
		maximumPeers:    maximumPeers,
		now:             now,
	}
}

func (l *peerRateLimiter) allow(remoteAddress string) (bool, time.Duration) {
	now := l.now()
	peer := socketPeer(remoteAddress)

	l.mu.Lock()
	defer l.mu.Unlock()
	if l.nextCleanup.IsZero() || !now.Before(l.nextCleanup) {
		staleBefore := now.Add(-l.entryTTL)
		for key, entry := range l.peers {
			if entry.lastSeen.Before(staleBefore) {
				delete(l.peers, key)
			}
		}
		l.nextCleanup = now.Add(l.cleanupInterval)
	}

	entry := l.peers[peer]
	if entry == nil {
		if len(l.peers) >= l.maximumPeers {
			return false, l.cleanupInterval
		}
		entry = &peerTokenBucket{
			tokens:     l.capacity,
			lastRefill: now,
			lastSeen:   now,
		}
		l.peers[peer] = entry
	}
	if elapsed := now.Sub(entry.lastRefill); elapsed > 0 {
		entry.tokens = math.Min(
			l.capacity,
			entry.tokens+elapsed.Seconds()*l.tokensPerSecond,
		)
		entry.lastRefill = now
	}
	entry.lastSeen = now
	if entry.tokens >= 1 {
		entry.tokens--
		return true, 0
	}
	retryAfter := time.Duration(math.Ceil((1-entry.tokens)/l.tokensPerSecond)) * time.Second
	if retryAfter < time.Second {
		retryAfter = time.Second
	}
	return false, retryAfter
}

func socketPeer(remoteAddress string) string {
	remoteAddress = strings.TrimSpace(remoteAddress)
	host, _, err := net.SplitHostPort(remoteAddress)
	if err == nil {
		if ip := net.ParseIP(host); ip != nil {
			return ip.String()
		}
		return strings.ToLower(host)
	}
	if ip := net.ParseIP(remoteAddress); ip != nil {
		return ip.String()
	}
	return "unknown-peer"
}
