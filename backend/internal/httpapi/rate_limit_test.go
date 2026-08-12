package httpapi

import (
	"testing"
	"time"
)

func TestPeerRateLimiterRefillsAndExpiresSocketPeers(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	limiter := newPeerRateLimiter(
		2,
		1,
		2*time.Minute,
		time.Minute,
		2,
		func() time.Time { return now },
	)

	for request := 0; request < 2; request++ {
		if allowed, _ := limiter.allow("192.0.2.10:1234"); !allowed {
			t.Fatalf("request %d unexpectedly rate limited", request+1)
		}
	}
	if allowed, retryAfter := limiter.allow("192.0.2.10:9999"); allowed || retryAfter != time.Second {
		t.Fatalf("exhausted peer = (%t, %s), want (false, 1s)", allowed, retryAfter)
	}
	now = now.Add(time.Second)
	if allowed, _ := limiter.allow("192.0.2.10:4321"); !allowed {
		t.Fatal("refilled peer remained rate limited")
	}

	if allowed, _ := limiter.allow("192.0.2.11:1234"); !allowed {
		t.Fatal("second peer unexpectedly rate limited")
	}
	now = now.Add(3 * time.Minute)
	if allowed, _ := limiter.allow("192.0.2.12:1234"); !allowed {
		t.Fatal("new peer was rejected after stale entries should be cleaned")
	}
	if got := len(limiter.peers); got != 1 {
		t.Fatalf("peer map length after TTL cleanup = %d, want 1", got)
	}
}

func TestPeerRateLimiterFailsClosedWhenPeerMapIsFull(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	limiter := newPeerRateLimiter(
		1,
		1,
		time.Hour,
		time.Minute,
		1,
		func() time.Time { return now },
	)
	if allowed, _ := limiter.allow("192.0.2.20:1234"); !allowed {
		t.Fatal("first peer unexpectedly rate limited")
	}
	if allowed, retryAfter := limiter.allow("192.0.2.21:1234"); allowed || retryAfter != time.Minute {
		t.Fatalf("full peer map = (%t, %s), want (false, 1m)", allowed, retryAfter)
	}
}

func TestSocketPeerUsesRemoteAddressWithoutForwardedHeaders(t *testing.T) {
	if got := socketPeer("[2001:db8::1]:443"); got != "2001:db8::1" {
		t.Fatalf("socketPeer(IPv6) = %q", got)
	}
	if got := socketPeer("192.0.2.30:443"); got != "192.0.2.30" {
		t.Fatalf("socketPeer(IPv4) = %q", got)
	}
}
