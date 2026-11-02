package httpapi

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"slices"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

const aiAdminConfigKey = "ai.admin.config.v1"

var adminID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$`)
var errAdminConflict = errors.New("configuration changed; reload before saving")

type adminProvider struct {
	ProxyURL         string `json:"proxy_url,omitempty"`
	ProxyUsername    string `json:"proxy_username,omitempty"`
	ProxyPassword    string `json:"proxy_password,omitempty"`
	HasProxyPassword bool   `json:"has_proxy_password"`
	Name             string `json:"name"`
	Type             string `json:"type"`
	Endpoint         string `json:"endpoint"`
	APIKey           string `json:"api_key,omitempty"`
	HasKey           bool   `json:"has_key"`
	Disabled         bool   `json:"disabled"`
}
type adminModel struct {
	ProviderID      string         `json:"provider_id"`
	Model           string         `json:"model"`
	Disabled        bool           `json:"disabled"`
	MaxOutputTokens int            `json:"max_output_tokens"`
	Pricing         config.AIPrice `json:"pricing"`
}
type adminGateway struct {
	Revision         int64                          `json:"revision"`
	Providers        map[string]adminProvider       `json:"providers"`
	Models           map[string]adminModel          `json:"models"`
	DefaultModel     string                         `json:"default_model"`
	DailyQuotaPoints int64                          `json:"daily_quota_points"`
	DailyRequests    int                            `json:"daily_requests"`
	Users            map[string]config.AIUserPolicy `json:"users"`
}

func (a *API) isAIAdmin(user model.User) bool {
	return a.cfg.Mode == config.ModeRemote && a.cfg.AIAdmin != nil && slices.Contains(a.cfg.AIAdmin.UserIDs, user.ID)
}
func (a *API) adminOnly(next protectedHandler) http.Handler {
	return a.protected(func(w http.ResponseWriter, r *http.Request, u model.User, t string) {
		if !a.isAIAdmin(u) {
			writeError(w, 403, "admin_required", "Administrator access required")
			return
		}
		if !a.sensitiveTransportAllowed(r) {
			writeError(w, 400, "secure_transport_required", "HTTPS is required")
			return
		}
		next(w, r, u, t)
	})
}
func (a *API) adminCipher() (cipher.AEAD, error) {
	if a.cfg.AIAdmin == nil {
		return nil, errors.New("AI administration disabled")
	}
	info, err := os.Stat(a.cfg.AIAdmin.EncryptionKeyFile)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() != 32 {
		return nil, errors.New("invalid administrator encryption key permissions")
	}
	key, err := os.ReadFile(a.cfg.AIAdmin.EncryptionKeyFile)
	if err != nil {
		return nil, err
	}
	if len(key) != 32 {
		return nil, errors.New("administrator encryption key must contain 32 random bytes")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
func (a *API) seedGateway() adminGateway {
	s := adminGateway{Providers: map[string]adminProvider{}, Models: map[string]adminModel{}, Users: map[string]config.AIUserPolicy{}}
	g := a.cfg.AIGateway
	if g == nil {
		return s
	}
	s.DefaultModel = g.DefaultModel
	s.DailyQuotaPoints = g.DailyQuotaPoints
	s.DailyRequests = g.DailyRequests
	if g.BudgetNanoUSD != nil {
		s.DailyQuotaPoints = *g.BudgetNanoUSD / 2000
	}
	aliases := make([]string, 0, len(g.Models))
	for alias := range g.Models {
		aliases = append(aliases, alias)
	}
	slices.Sort(aliases)
	for _, alias := range aliases {
		m := g.Models[alias]
		// Preserve distinct credentials/endpoints even for the same vendor.
		id := m.Provider
		if p, ok := s.Providers[id]; ok && (p.Endpoint != m.Endpoint || p.APIKey != m.APIKey || p.ProxyURL != m.ProxyURL || p.ProxyUsername != m.ProxyUsername || p.ProxyPassword != m.ProxyPassword) {
			id = alias
		}
		s.Providers[id] = adminProvider{ProxyURL: m.ProxyURL, ProxyUsername: m.ProxyUsername, ProxyPassword: m.ProxyPassword, Name: id, Type: m.Provider, Endpoint: m.Endpoint, APIKey: m.APIKey, HasKey: m.APIKey != ""}
		s.Models[alias] = adminModel{ProviderID: id, Model: m.Model, MaxOutputTokens: m.MaxOutputTokens, Pricing: g.ModelPrice(alias), Disabled: m.Disabled}
	}
	for id, p := range g.Users {
		s.Users[id] = p
	}
	return s
}
func (a *API) loadAdminGateway(db *gorm.DB) (adminGateway, error) {
	var row model.Setting
	err := db.Where("`key` = ?", aiAdminConfigKey).First(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return a.seedGateway(), nil
	}
	if err != nil {
		return adminGateway{}, err
	}
	c, err := a.adminCipher()
	if err != nil {
		return adminGateway{}, err
	}
	blob, err := base64.StdEncoding.DecodeString(row.Value)
	if err != nil || len(blob) < c.NonceSize() {
		return adminGateway{}, errors.New("invalid encrypted gateway settings")
	}
	raw, err := c.Open(nil, blob[:c.NonceSize()], blob[c.NonceSize():], []byte(aiAdminConfigKey))
	if err != nil {
		return adminGateway{}, err
	}
	var s adminGateway
	err = json.Unmarshal(raw, &s)
	return s, err
}
func (a *API) materializeGateway(s adminGateway) (*config.AIGateway, error) {
	var g config.AIGateway
	if a.cfg.AIGateway != nil {
		raw, _ := json.Marshal(a.cfg.AIGateway)
		if err := json.Unmarshal(raw, &g); err != nil {
			return nil, err
		}
	}
	g.Models = map[string]config.AIModel{}
	g.Users = s.Users
	g.DefaultModel = s.DefaultModel
	g.DailyQuotaPoints = s.DailyQuotaPoints
	g.DailyRequests = s.DailyRequests
	g.BudgetNanoUSD = nil
	if len(s.Providers) > 64 || len(s.Models) > 128 || s.DailyRequests > 1000000 {
		return nil, errors.New("gateway limits exceeded")
	}
	for id, p := range s.Providers {
		if err := config.ValidateAIProxy(p.ProxyURL, p.ProxyUsername, p.ProxyPassword); err != nil {
			return nil, err
		}
		u, err := url.Parse(p.Endpoint)
		if !adminID.MatchString(id) || len(p.Name) > 128 || (p.Type != "openai" && p.Type != "deepseek") || err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || len(p.Endpoint) > 2048 || strings.TrimSpace(p.APIKey) == "" || len(p.APIKey) > 8192 || strings.ContainsAny(p.APIKey, "\r\n") {
			return nil, errors.New("invalid provider configuration")
		}
		if ip := net.ParseIP(u.Hostname()); ip != nil && (ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() || ip.IsLinkLocalUnicast()) {
			return nil, errors.New("provider endpoint cannot be a private IP")
		}
		if strings.EqualFold(u.Hostname(), "localhost") {
			return nil, errors.New("provider endpoint cannot be localhost")
		}
	}
	for alias, m := range s.Models {
		p, ok := s.Providers[m.ProviderID]
		if !ok || !adminID.MatchString(alias) || len(m.Model) > 256 {
			return nil, errors.New("invalid model or missing provider")
		}
		g.Models[alias] = config.AIModel{ProxyURL: p.ProxyURL, ProxyUsername: p.ProxyUsername, ProxyPassword: p.ProxyPassword, ProviderID: m.ProviderID, Provider: p.Type, Endpoint: p.Endpoint, APIKey: p.APIKey, Model: m.Model, MaxOutputTokens: m.MaxOutputTokens, Pricing: m.Pricing, Disabled: m.Disabled || p.Disabled}
	}
	if err := g.Validate(); err != nil {
		return nil, err
	}
	return &g, nil
}

// Every admitted request receives an immutable snapshot. An in-flight stream
// retains its pricing; the next request sees committed settings on any replica.
func (a *API) aiRuntime(next func(*API) protectedHandler) http.Handler {
	return a.protected(func(w http.ResponseWriter, r *http.Request, u model.User, t string) {
		if a.cfg.AIAdmin == nil {
			next(a)(w, r, u, t)
			return
		}
		s, err := a.loadAdminGateway(a.store.DB().WithContext(r.Context()))
		if err != nil {
			writeError(w, 503, "gateway_configuration_unavailable", "Could not read gateway configuration")
			return
		}
		snapshot := *a
		snapshot.cfg.AIGateway, err = a.materializeGateway(s)
		if err != nil {
			writeError(w, 503, "gateway_configuration_unavailable", "Invalid gateway configuration")
			return
		}
		next(&snapshot)(w, r, u, t)
	})
}

type adminAudit struct {
	ID      string    `json:"id"`
	Actor   string    `json:"actor_id"`
	Action  string    `json:"action"`
	Target  string    `json:"target"`
	Reason  string    `json:"reason"`
	At      time.Time `json:"created_at"`
	Details any       `json:"details,omitempty"`
}

func saveAdminAudit(tx *gorm.DB, u model.User, action, target, reason string, details any) error {
	id, err := aiNewRequestID()
	if err != nil {
		return err
	}
	v, _ := json.Marshal(adminAudit{ID: id, Actor: u.ID, Action: action, Target: target, Reason: reason, At: time.Now().UTC(), Details: details})
	return tx.Create(&model.Setting{Key: "ai.admin.audit." + id, Value: string(v)}).Error
}
func (a *API) changeGateway(ctx context.Context, u model.User, revision int64, reason, action, target string, change func(*adminGateway) error) error {
	if len(strings.TrimSpace(reason)) < 3 || len(reason) > 500 {
		return errors.New("provide an operation reason (3-500 characters)")
	}
	return a.store.DB().WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// A separate write-lock row also serializes first-save and avoids lost updates.
		if err := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&model.Setting{Key: "ai.admin.lock", Value: "1"}).Error; err != nil {
			return err
		}
		if err := tx.Model(&model.Setting{}).Where("`key` = ?", "ai.admin.lock").Update("updated_at", time.Now().UTC()).Error; err != nil {
			return err
		}
		s, err := a.loadAdminGateway(tx)
		if err != nil {
			return err
		}
		if s.Revision != revision {
			return errAdminConflict
		}
		beforeRevision := s.Revision
		beforePolicy := s.Users[target]
		if err = change(&s); err != nil {
			return err
		}
		if _, err = a.materializeGateway(s); err != nil {
			return err
		}
		s.Revision++
		raw, err := json.Marshal(s)
		if err != nil {
			return err
		}
		c, err := a.adminCipher()
		if err != nil {
			return err
		}
		nonce := make([]byte, c.NonceSize())
		if _, err = rand.Read(nonce); err != nil {
			return err
		}
		encrypted := base64.StdEncoding.EncodeToString(c.Seal(nonce, nonce, raw, []byte(aiAdminConfigKey)))
		if err = tx.Clauses(clause.OnConflict{Columns: []clause.Column{{Name: "key"}}, DoUpdates: clause.Assignments(map[string]any{"value": encrypted, "updated_at": time.Now().UTC()})}).Create(&model.Setting{Key: aiAdminConfigKey, Value: encrypted}).Error; err != nil {
			return err
		}
		details := map[string]any{"revision": s.Revision, "previous_revision": beforeRevision}
		if action == "user.policy" {
			details["before"] = beforePolicy
			details["after"] = s.Users[target]
		} else {
			providers := map[string]adminProvider{}
			for id, p := range s.Providers {
				p.HasKey = p.APIKey != ""
				p.APIKey = ""
				p.HasProxyPassword = p.ProxyPassword != ""
				p.ProxyPassword = ""
				providers[id] = p
			}
			details["providers"] = providers
			details["models"] = s.Models
			details["daily_quota_points"] = s.DailyQuotaPoints
			details["daily_requests"] = s.DailyRequests
			details["default_model"] = s.DefaultModel
		}
		return saveAdminAudit(tx, u, action, target, reason, details)
	})
}
func writeAdminError(w http.ResponseWriter, err error) {
	if errors.Is(err, errAdminConflict) {
		writeError(w, 409, "revision_conflict", "配置已被修改，请刷新后重试。")
		return
	}
	// No raw database/provider errors: these may contain secret-bearing values.
	writeError(w, 400, "invalid_admin_operation", "操作未保存，请检查配置、操作原因或余额后重试。")
}
func (a *API) adminGatewayGet(w http.ResponseWriter, r *http.Request, u model.User, _ string) {
	s, err := a.loadAdminGateway(a.store.DB().WithContext(r.Context()))
	if err != nil {
		writeError(w, 503, "gateway_configuration_unavailable", "Could not read gateway settings")
		return
	}
	for id, p := range s.Providers {
		p.HasKey = p.APIKey != ""
		p.APIKey = ""
		p.HasProxyPassword = p.ProxyPassword != ""
		p.ProxyPassword = ""
		s.Providers[id] = p
	}
	writeJSON(w, 200, s)
}
func (a *API) adminGatewayPut(w http.ResponseWriter, r *http.Request, u model.User, _ string) {
	var req struct {
		Gateway adminGateway `json:"gateway"`
		Reason  string       `json:"reason"`
	}
	if err := decodeBody(w, r, 256<<10, &req); err != nil {
		writeDecodeError(w, err)
		return
	}
	err := a.changeGateway(r.Context(), u, req.Gateway.Revision, req.Reason, "gateway.update", "gateway", func(s *adminGateway) error {
		n := req.Gateway
		// User policies have a separate operation so this endpoint cannot erase them.
		n.Users = s.Users
		for id, p := range n.Providers {
			old, exists := s.Providers[id]
			if p.ProxyURL == "" || p.ProxyUsername == "" {
				p.ProxyUsername = ""
				p.ProxyPassword = ""
			} else if p.ProxyPassword == "" && exists && old.ProxyPassword != "" {
				if p.ProxyURL != old.ProxyURL || p.ProxyUsername != old.ProxyUsername {
					return errors.New("proxy changes require a new password")
				}
				p.ProxyPassword = old.ProxyPassword
			}
			p.HasProxyPassword = p.ProxyPassword != ""
			if p.APIKey == "" && exists {
				if p.Endpoint != old.Endpoint || p.Type != old.Type {
					return errors.New("endpoint changes require a new credential")
				}
				p.APIKey = old.APIKey
			}
			p.HasKey = p.APIKey != ""
			n.Providers[id] = p
		}
		*s = n
		return nil
	})
	if err != nil {
		writeAdminError(w, err)
		return
	}
	a.adminGatewayGet(w, r, u, "")
}
func adminReason(reason string) bool {
	return len(strings.TrimSpace(reason)) >= 3 && len(reason) <= 500
}
func adminUser(db *gorm.DB, id string) (model.User, error) {
	var u model.User
	if len(id) != 36 {
		return u, fmt.Errorf("invalid user")
	}
	err := db.Where("id = ?", id).First(&u).Error
	return u, err
}

// Credential probe lists models without generating billable completions.
func (a *API) adminProviderTest(w http.ResponseWriter, r *http.Request, actor model.User, _ string) {
	s, err := a.loadAdminGateway(a.store.DB().WithContext(r.Context()))
	if err != nil {
		writeAdminError(w, err)
		return
	}
	p, ok := s.Providers[r.PathValue("id")]
	if !ok {
		writeError(w, 404, "provider_not_found", "Provider not found")
		return
	}
	if _, err = a.materializeGateway(s); err != nil {
		writeAdminError(w, err)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(p.Endpoint, "/")+"/models", nil)
	if err != nil {
		writeAdminError(w, err)
		return
	}
	req.Header.Set("Authorization", "Bearer "+p.APIKey)
	start := time.Now()
	client, closeIdle, err := providerHTTPClient(p.ProxyURL, p.ProxyUsername, p.ProxyPassword)
	if err != nil {
		writeAdminError(w, err)
		return
	}
	defer closeIdle()
	res, err := client.Do(req)
	status := 0
	if res != nil {
		status = res.StatusCode
		res.Body.Close()
	}
	ok = err == nil && status >= 200 && status < 300
	writeJSON(w, 200, map[string]any{"ok": ok, "status": status, "latency_ms": time.Since(start).Milliseconds()})
}
