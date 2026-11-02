package httpapi

import (
	"encoding/base64"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestProviderProxyCONNECTIsolation(t *testing.T) {
	var upstreamHits, proxyHits atomic.Int32
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamHits.Add(1)
		if r.Header.Get("Proxy-Authorization") != "" {
			t.Error("proxy credentials leaked upstream")
		}
		if r.Header.Get("Authorization") != "Bearer provider-secret" {
			t.Error("provider credential lost")
		}
		w.Write([]byte("ok"))
	}))
	defer upstream.Close()
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		proxyHits.Add(1)
		if r.Method != "CONNECT" || r.Header.Get("Proxy-Authorization") != "Basic "+base64.StdEncoding.EncodeToString([]byte("user:proxy-secret")) {
			w.WriteHeader(407)
			return
		}
		if r.Header.Get("Authorization") != "" {
			t.Error("API credential sent in CONNECT")
		}
		dst, err := net.DialTimeout("tcp", r.Host, time.Second)
		if err != nil {
			w.WriteHeader(502)
			return
		}
		defer dst.Close()
		src, buffer, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer src.Close()
		buffer.WriteString("HTTP/1.1 200 Connection Established\r\n\r\n")
		buffer.Flush()
		done := make(chan struct{})
		go func() { io.Copy(dst, buffer); dst.Close(); close(done) }()
		io.Copy(src, dst)
		src.Close()
		<-done
	}))
	old := aiHTTPClient
	aiHTTPClient = upstream.Client()
	defer func() { aiHTTPClient = old }()
	request := func(address, user, password string) error {
		client, cleanup, err := providerHTTPClient(address, user, password)
		if err != nil {
			return err
		}
		defer cleanup()
		req, _ := http.NewRequest("GET", upstream.URL, nil)
		req.Header.Set("Authorization", "Bearer provider-secret")
		res, err := client.Do(req)
		if err == nil {
			io.Copy(io.Discard, res.Body)
			res.Body.Close()
		}
		return err
	}
	if err := request(proxy.URL, "user", "proxy-secret"); err != nil {
		t.Fatal(err)
	}
	if err := request(proxy.URL, "user", "wrong"); err == nil {
		t.Fatal("proxy auth failure ignored")
	}
	if upstreamHits.Load() != 1 {
		t.Fatal("failed proxy fell back to direct")
	}
	if err := request("", "", ""); err != nil {
		t.Fatal(err)
	}
	if proxyHits.Load() != 2 || upstreamHits.Load() != 2 {
		t.Fatal("provider routes not isolated")
	}
	proxy.Close()
	if err := request(proxy.URL, "user", "proxy-secret"); err == nil {
		t.Fatal("dead proxy fell back")
	}
	if upstreamHits.Load() != 2 {
		t.Fatal("unexpected direct connection")
	}
}
