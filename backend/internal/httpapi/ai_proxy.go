package httpapi

import (
	"errors"
	"ianvs-terminal/backend/internal/config"
	"net/http"
	"net/url"
)

// Own the transport for the lifetime of the request, including streamed bodies.
// Never mutate the shared client or share authenticated proxy connections across providers.
func providerHTTPClient(address, username, password string) (*http.Client, func(), error) {
	if err := config.ValidateAIProxy(address, username, password); err != nil {
		return nil, nil, err
	}
	if address == "" {
		return aiHTTPClient, func() {}, nil
	}
	proxy, _ := url.Parse(address)
	if username != "" {
		proxy.User = url.UserPassword(username, password)
	}
	base := aiHTTPClient.Transport
	if base == nil {
		base = http.DefaultTransport
	}
	transport, ok := base.(*http.Transport)
	if !ok {
		return nil, nil, errors.New("unsupported provider transport")
	}
	owned := transport.Clone()
	owned.Proxy = http.ProxyURL(proxy)
	client := *aiHTTPClient
	client.Transport = owned
	return &client, owned.CloseIdleConnections, nil
}
