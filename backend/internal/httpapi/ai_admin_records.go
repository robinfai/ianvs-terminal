package httpapi

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"gorm.io/gorm"
	"ianvs-terminal/backend/internal/model"
)

type adminCursor struct {
	At  time.Time `json:"at"`
	Key string    `json:"key"`
}

func pageSettings(q *gorm.DB, r *http.Request) ([]model.Setting, string, error) {
	if cursor := r.URL.Query().Get("before"); cursor != "" {
		var c adminCursor
		raw, err := base64.RawURLEncoding.DecodeString(cursor)
		if len(cursor) > 600 || err != nil || json.Unmarshal(raw, &c) != nil || c.At.IsZero() || len(c.Key) > 191 {
			return nil, "", errors.New("invalid cursor")
		}
		q = q.Where("created_at < ? OR (created_at = ? AND `key` < ?)", c.At, c.At, c.Key)
	}
	var rows []model.Setting
	if err := q.Order("created_at DESC, `key` DESC").Limit(51).Find(&rows).Error; err != nil {
		return nil, "", err
	}
	next := ""
	if len(rows) > 50 {
		rows = rows[:50]
		last := rows[len(rows)-1]
		raw, _ := json.Marshal(adminCursor{At: last.CreatedAt, Key: last.Key})
		next = base64.RawURLEncoding.EncodeToString(raw)
	}
	return rows, next, nil
}
func ledgerRange(r *http.Request) (time.Time, time.Time, error) {
	end := time.Now().UTC().Add(time.Second)
	start := end.AddDate(0, 0, -7)
	if s := r.URL.Query().Get("from"); s != "" {
		v, e := time.Parse("2006-01-02", s)
		if e != nil {
			return start, end, e
		}
		start = v
	}
	if s := r.URL.Query().Get("to"); s != "" {
		v, e := time.Parse("2006-01-02", s)
		if e != nil {
			return start, end, e
		}
		end = v.AddDate(0, 0, 1)
	}
	if !start.Before(end) || end.Sub(start) > 91*24*time.Hour {
		return start, end, errors.New("date range must be at most 90 days")
	}
	return start, end, nil
}
func jsonField(db *gorm.DB, path string) string {
	expr := "json_extract(value, '$." + path + "')"
	if db.Dialector.Name() == "mysql" {
		return "JSON_UNQUOTE(" + expr + ")"
	}
	return expr
}
func (a *API) adminRecords(w http.ResponseWriter, r *http.Request, _ model.User, _ string) {
	start, end, err := ledgerRange(r)
	if err != nil {
		writeError(w, 400, "invalid_range", "Use a UTC date range of at most 90 days")
		return
	}
	db := a.store.DB().WithContext(r.Context())
	prefix := "ai.ledger."
	if id := r.URL.Query().Get("user_id"); id != "" {
		if _, err = adminUser(db, id); err != nil {
			writeError(w, 400, "invalid_user", "Unknown user")
			return
		}
		prefix = aiLedgerPrefix(id)
	}
	q := db.Model(&model.Setting{}).Where("`key` >= ? AND `key` < ? AND created_at >= ? AND created_at < ?", prefix, prefix+"~", start, end)
	for _, field := range []string{"model", "provider", "provider_id", "status"} {
		if v := r.URL.Query().Get(field); v != "" {
			if len(v) > 128 {
				writeError(w, 400, "invalid_filter", "Invalid filter")
				return
			}
			expr := jsonField(db, field)
			if field == "provider_id" {
				expr = "COALESCE(NULLIF(" + expr + ", ''), " + jsonField(db, "provider") + ")"
			}
			q = q.Where(expr+" = ?", v)
		}
	}
	var summary struct {
		Requests int64 `json:"requests"`
		Spent    int64 `json:"spent_nano_usd"`
		Reserved int64 `json:"pending_reserved_nano_usd"`
		Input    int64 `json:"input_tokens"`
		Cached   int64 `json:"cached_input_tokens"`
		Output   int64 `json:"output_tokens"`
	}
	expr := "COUNT(*) AS requests, COALESCE(SUM(" + jsonField(db, "usage.spent_nano_usd") + "),0) AS spent, COALESCE(SUM(CASE WHEN " + jsonField(db, "status") + " = 'pending' THEN " + jsonField(db, "reserved_nano_usd") + " ELSE 0 END),0) AS reserved, COALESCE(SUM(" + jsonField(db, "usage.input_tokens") + "),0) AS input, COALESCE(SUM(" + jsonField(db, "usage.cached_input_tokens") + "),0) AS cached, COALESCE(SUM(" + jsonField(db, "usage.output_tokens") + "),0) AS output"
	if err = q.Session(&gorm.Session{}).Select(expr).Scan(&summary).Error; err != nil {
		writeError(w, 503, "ledger_unavailable", "Could not summarize usage")
		return
	}
	rows, next, err := pageSettings(q, r)
	if err != nil {
		writeError(w, 400, "invalid_ledger_query", "Could not query usage")
		return
	}
	data := []map[string]any{}
	names := map[string]string{}
	for _, row := range rows {
		var entry aiLedgerEntry
		if json.Unmarshal([]byte(row.Value), &entry) != nil {
			writeError(w, 503, "ledger_unavailable", "Invalid usage record")
			return
		}
		userID := strings.TrimSuffix(strings.TrimPrefix(row.Key, "ai.ledger."), "."+entry.ID)
		if _, ok := names[userID]; !ok {
			u, e := adminUser(db, userID)
			if e == nil {
				names[userID] = u.Username
			}
		}
		entry.BudgetKey = ""
		data = append(data, map[string]any{"user_id": userID, "username": names[userID], "entry": entry})
	}
	writeJSON(w, 200, map[string]any{"data": data, "next_cursor": next, "summary": summary, "from": start, "to": end})
}
func (a *API) adminAuditList(w http.ResponseWriter, r *http.Request, _ model.User, _ string) {
	prefix := "ai.admin.audit."
	q := a.store.DB().WithContext(r.Context()).Where("`key` >= ? AND `key` < ?", prefix, prefix+"~")
	rows, next, err := pageSettings(q, r)
	if err != nil {
		writeError(w, 400, "invalid_audit_query", "Could not query audit log")
		return
	}
	entries := []adminAudit{}
	for _, row := range rows {
		var v adminAudit
		if json.Unmarshal([]byte(row.Value), &v) != nil {
			writeError(w, 503, "audit_unavailable", "Invalid audit record")
			return
		}
		entries = append(entries, v)
	}
	writeJSON(w, 200, map[string]any{"data": entries, "next_cursor": next})
}
