package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gorm.io/gorm"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

func (a *API) adminUsers(w http.ResponseWriter, r *http.Request, _ model.User, _ string) {
	q := a.store.DB().WithContext(r.Context()).Model(&model.User{})
	if search := strings.TrimSpace(r.URL.Query().Get("q")); search != "" {
		if len(search) > 100 {
			writeError(w, 400, "invalid_query", "Search is too long")
			return
		}
		q = q.Where("username LIKE ?", "%"+search+"%")
	}
	if after := r.URL.Query().Get("after"); after != "" {
		q = q.Where("id > ?", after)
	}
	var users []model.User
	if err := q.Order("id ASC").Limit(51).Find(&users).Error; err != nil {
		writeError(w, 503, "users_unavailable", "Could not list users")
		return
	}
	more := len(users) > 50
	if more {
		users = users[:50]
	}
	s, err := a.loadAdminGateway(a.store.DB().WithContext(r.Context()))
	if err != nil {
		writeAdminError(w, err)
		return
	}
	data := []map[string]any{}
	for _, u := range users {
		data = append(data, map[string]any{"id": u.ID, "username": u.Username, "created_at": u.CreatedAt, "ai_disabled": s.Users[u.ID].Disabled, "is_admin": a.isAIAdmin(u)})
	}
	next := ""
	if more {
		next = users[len(users)-1].ID
	}
	writeJSON(w, 200, map[string]any{"data": data, "next_cursor": next})
}
func (a *API) adminUserGet(w http.ResponseWriter, r *http.Request, _ model.User, _ string) {
	db := a.store.DB().WithContext(r.Context())
	u, err := adminUser(db, r.PathValue("id"))
	if err != nil {
		writeError(w, 404, "user_not_found", "User not found")
		return
	}
	s, err := a.loadAdminGateway(db)
	if err != nil {
		writeAdminError(w, err)
		return
	}
	g, err := a.materializeGateway(s)
	if err != nil {
		writeAdminError(w, err)
		return
	}
	snapshot := *a
	snapshot.cfg.AIGateway = g
	var row model.Setting
	var account aiAccount
	err = db.Where("`key` = ?", aiAccountKey(u.ID)).First(&row).Error
	if err == nil {
		err = json.Unmarshal([]byte(row.Value), &account)
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		writeAdminError(w, err)
		return
	}
	wallet, err := a.readAIWallet(r.Context(), u.ID)
	if err != nil {
		writeAdminError(w, err)
		return
	}
	requests := 0
	if err = db.Where("`key` = ?", "ai.requests."+time.Now().UTC().Format("2006-01-02")+"."+u.ID).First(&row).Error; err == nil {
		requests, _ = strconv.Atoi(row.Value)
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		writeAdminError(w, err)
		return
	}
	budget := snapshot.aiBudget(u.ID)
	remaining := max(int64(0), budget-(account.Spent-account.PaidSpent)-(account.Reserved-account.PaidReserved))
	writeJSON(w, 200, map[string]any{"id": u.ID, "username": u.Username, "revision": s.Revision, "policy": s.Users[u.ID], "daily_budget_nano_usd": budget, "daily_remaining_nano_usd": remaining, "daily_requests": g.RequestLimit(u.ID), "requests_today": requests, "wallet": wallet, "usage": account, "reset_at": time.Now().UTC().Truncate(24 * time.Hour).Add(24 * time.Hour)})
}
func (a *API) adminUserPolicy(w http.ResponseWriter, r *http.Request, actor model.User, _ string) {
	id := r.PathValue("id")
	if _, err := adminUser(a.store.DB().WithContext(r.Context()), id); err != nil {
		writeError(w, 404, "user_not_found", "User not found")
		return
	}
	var req struct {
		Revision int64               `json:"revision"`
		Reason   string              `json:"reason"`
		Policy   config.AIUserPolicy `json:"policy"`
	}
	if err := decodeBody(w, r, 16<<10, &req); err != nil {
		writeDecodeError(w, err)
		return
	}
	err := a.changeGateway(r.Context(), actor, req.Revision, req.Reason, "user.policy", id, func(s *adminGateway) error {
		if s.Users == nil {
			s.Users = map[string]config.AIUserPolicy{}
		}
		s.Users[id] = req.Policy
		return nil
	})
	if err != nil {
		writeAdminError(w, err)
		return
	}
	a.adminUserGet(w, r, actor, "")
}

type adminCredit struct {
	OperationID string    `json:"operation_id"`
	UserID      string    `json:"user_id"`
	ActorID     string    `json:"actor_id"`
	Points      int64     `json:"points"`
	Reason      string    `json:"reason"`
	Before      int64     `json:"before_nano_usd"`
	After       int64     `json:"after_nano_usd"`
	At          time.Time `json:"created_at"`
}

func (a *API) adminCreditAdjust(w http.ResponseWriter, r *http.Request, actor model.User, _ string) {
	id := r.PathValue("id")
	db := a.store.DB().WithContext(r.Context())
	if _, err := adminUser(db, id); err != nil {
		writeError(w, 404, "user_not_found", "User not found")
		return
	}
	var req struct {
		OperationID string `json:"operation_id"`
		Points      int64  `json:"points"`
		Reason      string `json:"reason"`
	}
	if err := decodeBody(w, r, 4096, &req); err != nil {
		writeDecodeError(w, err)
		return
	}
	if len(req.OperationID) != 36 || !adminID.MatchString(req.OperationID) || req.Points == 0 || req.Points < -1000000000 || req.Points > 1000000000 || !adminReason(req.Reason) {
		writeError(w, 400, "invalid_adjustment", "Invalid amount, operation ID or reason")
		return
	}
	result := adminCredit{OperationID: req.OperationID, UserID: id, ActorID: actor.ID, Points: req.Points, Reason: req.Reason, At: time.Now().UTC()}
	err := db.Transaction(func(tx *gorm.DB) error {
		return lockedAIWallet(tx, id, func(wallet *aiWallet) error {
			key := "ai.admin.credit." + req.OperationID
			var existing model.Setting
			err := tx.Where("`key` = ?", key).First(&existing).Error
			if err == nil {
				if json.Unmarshal([]byte(existing.Value), &result) != nil {
					return errors.New("invalid adjustment")
				}
				if result.UserID != id || result.Points != req.Points || result.ActorID != actor.ID || result.Reason != req.Reason {
					return errAdminConflict
				}
				return nil
			}
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				return err
			}
			delta := req.Points * 2000
			if (delta < 0 && wallet.Balance+delta < wallet.Reserved) || wallet.Balance > 2000000000000000-delta {
				return errors.New("insufficient unreserved credit or balance limit")
			}
			result.Before = wallet.Balance
			wallet.Balance += delta
			result.After = wallet.Balance
			raw, _ := json.Marshal(result)
			if err = tx.Create(&model.Setting{Key: key, Value: string(raw)}).Error; err != nil {
				return err
			}
			return saveAdminAudit(tx, actor, "user.credit", id, req.Reason, result)
		})
	})
	if err != nil {
		writeAdminError(w, err)
		return
	}
	writeJSON(w, 200, result)
}
