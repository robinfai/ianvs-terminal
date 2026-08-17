package httpapi

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net"
	"net/http"
	"os"
	"reflect"
	"runtime/debug"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
	"unicode/utf8"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

const (
	maximumBodySize               = store.MaximumJSONResponseBytes
	maximumMergeBodySize          = store.MaximumJSONResponseBytes
	maximumAuthenticationBodySize = 4 << 10
	requestIDHeader               = "X-Request-ID"
	maximumRequestIDSize          = 128
)

var errUnsupportedMediaType = errors.New("content type must be application/json")
var requestIDFallback atomic.Uint64

type requestIDContextKey struct{}

type API struct {
	cfg                  config.Config
	auth                 *auth.Service
	store                *store.Store
	mux                  *http.ServeMux
	logger               *slog.Logger
	anonymousAuthLimiter *peerRateLimiter
}

type protectedHandler func(http.ResponseWriter, *http.Request, model.User, string)

func New(cfg config.Config, authService *auth.Service, resourceStore *store.Store) *API {
	return newWithLogger(
		cfg,
		authService,
		resourceStore,
		slog.New(slog.NewJSONHandler(os.Stderr, nil)),
	)
}

func newWithLogger(
	cfg config.Config,
	authService *auth.Service,
	resourceStore *store.Store,
	logger *slog.Logger,
) *API {
	api := &API{
		cfg:                  cfg,
		auth:                 authService,
		store:                resourceStore,
		mux:                  http.NewServeMux(),
		logger:               logger,
		anonymousAuthLimiter: newAnonymousAuthRateLimiter(),
	}
	api.routes()
	return api
}

func (a *API) Handler() http.Handler {
	apiHandler := a.withRecovery(a.withSecurityHeaders(a.withLocalBoundary(a.mux)))
	webUIHandler := a.withRecovery(a.withSecurityHeaders(http.HandlerFunc(a.serveWebUI)))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isWebUIRequest(r) {
			webUIHandler.ServeHTTP(w, r)
			return
		}
		apiHandler.ServeHTTP(w, r)
	})
}

func (a *API) routes() {
	a.mux.HandleFunc("GET /healthz", a.health)
	a.mux.HandleFunc("POST /v1/auth/register/begin", a.beginRegister)
	a.mux.HandleFunc("POST /v1/auth/register/complete", a.completeRegister)
	a.mux.HandleFunc("POST /v1/auth/login/begin", a.beginLogin)
	a.mux.HandleFunc("POST /v1/auth/login/complete", a.completeLogin)
	a.mux.HandleFunc("POST /v1/auth/cancel-operation", a.cancelAuthOperation)
	a.mux.Handle("POST /v1/auth/logout", a.protected(a.logout))
	a.mux.Handle("GET /v1/me", a.protected(a.me))
	a.mux.Handle("GET /v1/resources", a.protected(a.listResources))
	a.mux.Handle("GET /v1/resources/{kind}/{id}", a.protected(a.getResource))
	a.mux.Handle("PUT /v1/resources/{kind}/{id}", a.protected(a.putResource))
	a.mux.Handle("DELETE /v1/resources/{kind}/{id}", a.protected(a.deleteResource))
	a.mux.Handle("GET /v1/migrations/export", a.protected(a.exportMigration))
	a.mux.Handle("POST /v1/migrations/merge", a.protected(a.mergeMigration))
}

func (a *API) health(w http.ResponseWriter, r *http.Request) {
	var count int64
	if err := a.store.DB().WithContext(r.Context()).Model(&model.Setting{}).Count(&count).Error; err != nil {
		writeError(w, http.StatusServiceUnavailable, "database_unavailable", "database is unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":    "ok",
		"mode":      a.cfg.Mode,
		"server_id": a.store.ServerID(),
		"time":      time.Now().UTC(),
	})
}

func (a *API) beginRegister(w http.ResponseWriter, r *http.Request) {
	if a.cfg.Mode != config.ModeRemote || !a.cfg.AllowRegistration {
		writeError(w, http.StatusNotFound, "not_found", "registration is not available")
		return
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "registration requires HTTPS")
		return
	}
	if !a.allowAnonymousAuthRequest(w, r) {
		return
	}
	var request struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeBody(w, r, maximumAuthenticationBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	prepared, err := a.auth.BeginRegister(
		r.Context(),
		request.Username,
		request.Password,
	)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, prepared)
}

func (a *API) completeRegister(w http.ResponseWriter, r *http.Request) {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, http.StatusNotFound, "not_found", "registration completion is not available in local mode")
		return
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "registration requires HTTPS")
		return
	}
	if !a.allowAnonymousAuthRequest(w, r) {
		return
	}
	var request struct {
		OperationID string `json:"operation_id"`
	}
	if err := decodeBody(w, r, maximumAuthenticationBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	session, err := a.auth.CompleteRegister(r.Context(), request.OperationID)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (a *API) beginLogin(w http.ResponseWriter, r *http.Request) {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, http.StatusNotFound, "not_found", "login is not available in local mode")
		return
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "login requires HTTPS")
		return
	}
	if !a.allowAnonymousAuthRequest(w, r) {
		return
	}
	var request struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeBody(w, r, maximumAuthenticationBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	prepared, err := a.auth.BeginLogin(r.Context(), request.Username, request.Password)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, prepared)
}

func (a *API) completeLogin(w http.ResponseWriter, r *http.Request) {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, http.StatusNotFound, "not_found", "login is not available in local mode")
		return
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "login requires HTTPS")
		return
	}
	if !a.allowAnonymousAuthRequest(w, r) {
		return
	}
	var request struct {
		OperationID string `json:"operation_id"`
	}
	if err := decodeBody(w, r, maximumAuthenticationBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	session, err := a.auth.CompleteLogin(r.Context(), request.OperationID)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (a *API) cancelAuthOperation(w http.ResponseWriter, r *http.Request) {
	if a.cfg.Mode != config.ModeRemote {
		writeError(w, http.StatusNotFound, "not_found", "authentication operation cancellation is not available in local mode")
		return
	}
	if !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "authentication operation cancellation requires HTTPS")
		return
	}
	if !a.allowAnonymousAuthRequest(w, r) {
		return
	}
	var request struct {
		OperationID string `json:"operation_id"`
	}
	if err := decodeBody(w, r, maximumAuthenticationBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	if err := a.auth.CancelOperation(r.Context(), request.OperationID); err != nil {
		a.writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) logout(w http.ResponseWriter, r *http.Request, _ model.User, rawToken string) {
	if a.cfg.Mode == config.ModeRemote {
		if err := a.auth.Logout(r.Context(), rawToken); err != nil {
			a.writeServiceError(w, err)
			return
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) me(w http.ResponseWriter, _ *http.Request, user model.User, _ string) {
	writeJSON(w, http.StatusOK, map[string]any{"user": auth.View(user)})
}

func (a *API) listResources(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	includeDeleted, err := queryBool(r, "include_deleted")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	includeSensitive, err := queryBool(r, "include_sensitive")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	limit, cursor, err := queryPage(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	page, err := a.store.List(
		r.Context(),
		user,
		strings.TrimSpace(r.URL.Query().Get("kind")),
		includeDeleted,
		includeSensitive,
		limit,
		cursor,
	)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeBoundedJSON(w, http.StatusOK, page)
}

func (a *API) getResource(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	includeSensitive, err := queryBool(r, "include_sensitive")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	resource, err := a.store.Get(
		r.Context(),
		user,
		r.PathValue("kind"),
		r.PathValue("id"),
		includeSensitive,
	)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeBoundedJSON(w, http.StatusOK, resource)
}

func (a *API) putResource(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	var request struct {
		Data             json.RawMessage `json:"data"`
		Sensitive        json.RawMessage `json:"sensitive"`
		ClearSensitive   bool            `json:"clear_sensitive"`
		ExpectedRevision *int64          `json:"expected_revision"`
	}
	if err := decodeBody(w, r, maximumBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	sensitivePresent := len(request.Sensitive) > 0
	if sensitivePresent && request.ClearSensitive {
		writeError(w, http.StatusBadRequest, "invalid_request", "sensitive and clear_sensitive cannot be used together")
		return
	}
	if request.ExpectedRevision != nil && *request.ExpectedRevision < 0 {
		writeError(w, http.StatusBadRequest, "invalid_request", "expected_revision must be zero or a positive integer")
		return
	}
	if sensitivePresent && !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "sensitive data requires HTTPS")
		return
	}
	resource, err := a.store.Put(
		r.Context(),
		user,
		r.PathValue("kind"),
		r.PathValue("id"),
		store.WriteInput{
			Data:             request.Data,
			Sensitive:        request.Sensitive,
			SensitivePresent: sensitivePresent,
			ClearSensitive:   request.ClearSensitive,
			ExpectedRevision: request.ExpectedRevision,
		},
	)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeBoundedJSON(w, http.StatusOK, resource)
}

func (a *API) deleteResource(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	var expectedRevision *int64
	if raw := strings.TrimSpace(r.URL.Query().Get("expected_revision")); raw != "" {
		value, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || value <= 0 {
			writeError(w, http.StatusBadRequest, "invalid_query", "expected_revision must be a positive integer")
			return
		}
		expectedRevision = &value
	}
	if err := a.store.Delete(
		r.Context(),
		user,
		r.PathValue("kind"),
		r.PathValue("id"),
		expectedRevision,
	); err != nil {
		a.writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) exportMigration(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	includeDeleted, err := queryBool(r, "include_deleted")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	includeSensitive, err := queryBool(r, "include_sensitive")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	if includeSensitive && !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "sensitive exports require HTTPS")
		return
	}
	limit, cursor, err := queryPage(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return
	}
	bundle, err := a.store.Export(
		r.Context(),
		user,
		includeDeleted,
		includeSensitive,
		limit,
		cursor,
	)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeBoundedJSON(w, http.StatusOK, bundle)
}

func (a *API) mergeMigration(w http.ResponseWriter, r *http.Request, user model.User, _ string) {
	var request store.MergeRequest
	if err := decodeBody(w, r, maximumMergeBodySize, &request); err != nil {
		writeDecodeError(w, err)
		return
	}
	needsKey := false
	for _, resource := range request.Resources {
		if len(resource.Sensitive) > 0 {
			needsKey = true
			break
		}
	}
	if needsKey && !a.sensitiveTransportAllowed(r) {
		writeError(w, http.StatusBadRequest, "secure_transport_required", "sensitive migrations require HTTPS")
		return
	}
	report, err := a.store.Merge(r.Context(), user, request)
	if err != nil {
		a.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (a *API) protected(next protectedHandler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if a.cfg.Mode == config.ModeLocal {
			user, err := a.auth.EnsureLocalUser(r.Context())
			if err != nil {
				a.writeServiceError(w, err)
				return
			}
			next(w, r, user, "")
			return
		}
		if !a.sensitiveTransportAllowed(r) {
			writeError(w, http.StatusBadRequest, "secure_transport_required", "remote API access requires HTTPS")
			return
		}
		rawToken := bearerToken(r.Header.Get("Authorization"))
		user, err := a.auth.AuthenticateToken(r.Context(), rawToken)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "a valid bearer token is required")
			return
		}
		next(w, r, user, rawToken)
	})
}

func (a *API) sensitiveTransportAllowed(r *http.Request) bool {
	if a.cfg.AllowInsecureSensitiveTransport || a.cfg.Mode == config.ModeLocal {
		return true
	}
	if r.TLS != nil {
		return true
	}
	return a.cfg.TrustProxyHeaders &&
		strings.EqualFold(strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")), "https")
}

func (a *API) writeServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidCredentials):
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "username or password is invalid")
	case errors.Is(err, auth.ErrUsernameTaken):
		writeError(w, http.StatusConflict, "username_taken", err.Error())
	case errors.Is(err, auth.ErrInvalidUsername), errors.Is(err, auth.ErrInvalidPassword):
		writeError(w, http.StatusBadRequest, "invalid_account", err.Error())
	case errors.Is(err, auth.ErrInvalidOperationID):
		writeError(w, http.StatusBadRequest, "invalid_operation_id", err.Error())
	case errors.Is(err, auth.ErrOperationNotFound):
		writeError(w, http.StatusNotFound, "auth_operation_not_found", "authentication operation was not found")
	case errors.Is(err, auth.ErrOperationKind):
		writeError(w, http.StatusConflict, "auth_operation_kind_mismatch", "authentication operation kind does not match the completion endpoint")
	case errors.Is(err, auth.ErrOperationCanceled):
		writeError(w, http.StatusConflict, "auth_operation_canceled", "authentication operation was canceled")
	case errors.Is(err, auth.ErrOperationReused):
		writeError(w, http.StatusConflict, "auth_operation_reused", "authentication operation was already used")
	case errors.Is(err, auth.ErrSessionCapacity):
		w.Header().Set("Retry-After", "1")
		writeError(w, http.StatusTooManyRequests, "auth_session_capacity", "the user has too many active authentication operations")
	case errors.Is(err, auth.ErrPasswordHashBusy):
		w.Header().Set("Retry-After", "1")
		writeError(w, http.StatusTooManyRequests, "password_hash_busy", "password verification capacity is busy")
	case errors.Is(err, store.ErrNotFound), errors.Is(err, gorm.ErrRecordNotFound):
		writeError(w, http.StatusNotFound, "not_found", "resource was not found")
	case errors.Is(err, store.ErrRevisionConflict):
		writeError(w, http.StatusConflict, "revision_conflict", "resource revision changed")
	case errors.Is(err, store.ErrInvalidResource):
		writeError(w, http.StatusBadRequest, "invalid_resource", err.Error())
	case errors.Is(err, store.ErrInvalidPage):
		writeError(w, http.StatusBadRequest, "invalid_cursor", "the pagination cursor is invalid")
	case errors.Is(err, store.ErrResponseTooLarge):
		writeError(w, http.StatusUnprocessableEntity, "response_too_large", "a resource exceeds the response size limit")
	default:
		writeError(w, http.StatusInternalServerError, "internal_error", "the request could not be completed")
	}
}

func (a *API) allowAnonymousAuthRequest(w http.ResponseWriter, r *http.Request) bool {
	allowed, retryAfter := a.anonymousAuthLimiter.allow(r.RemoteAddr)
	if allowed {
		return true
	}
	retrySeconds := int64((retryAfter + time.Second - 1) / time.Second)
	if retrySeconds < 1 {
		retrySeconds = 1
	}
	w.Header().Set("Retry-After", strconv.FormatInt(retrySeconds, 10))
	writeError(
		w,
		http.StatusTooManyRequests,
		"authentication_rate_limited",
		"too many authentication attempts from this network peer",
	)
	return false
}

func (a *API) withLocalBoundary(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if a.cfg.Mode == config.ModeLocal {
			if !isLoopbackRequest(r) {
				writeError(w, http.StatusForbidden, "local_only", "local mode accepts loopback requests only")
				return
			}
			if a.cfg.LocalAccessToken != "" && !constantTimeEqual(
				bearerToken(r.Header.Get("Authorization")),
				a.cfg.LocalAccessToken,
			) {
				writeError(w, http.StatusUnauthorized, "local_access_denied", "a valid local access token is required")
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func constantTimeEqual(actual, expected string) bool {
	if len(actual) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(actual), []byte(expected)) == 1
}

func (a *API) withSecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; connect-src 'self'; img-src 'self'; script-src 'self'; style-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		next.ServeHTTP(w, r)
	})
}

func (a *API) withRecovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := validRequestID(r.Header.Get(requestIDHeader))
		if requestID == "" {
			requestID = newRequestID()
		}
		w.Header().Set(requestIDHeader, requestID)
		r = r.WithContext(context.WithValue(r.Context(), requestIDContextKey{}, requestID))
		response := &observedResponseWriter{
			ResponseWriter: w,
			status:         http.StatusOK,
		}
		started := time.Now()
		defer func() {
			if recovered := recover(); recovered != nil {
				if !response.wroteHeader {
					writeError(response, http.StatusInternalServerError, "internal_error", "the request could not be completed")
				}
				a.logRequestFailure(
					r,
					"http request panicked",
					response.status,
					started,
					"panic_type", fmt.Sprintf("%T", recovered),
					"stack", string(debug.Stack()),
				)
				return
			}
			if response.status >= http.StatusInternalServerError {
				a.logRequestFailure(
					r,
					"http request failed",
					response.status,
					started,
				)
			}
		}()
		next.ServeHTTP(response, r)
	})
}

type observedResponseWriter struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (w *observedResponseWriter) WriteHeader(status int) {
	if w.wroteHeader {
		return
	}
	w.status = status
	w.wroteHeader = true
	w.ResponseWriter.WriteHeader(status)
}

func (w *observedResponseWriter) Write(body []byte) (int, error) {
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(body)
}

func (w *observedResponseWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}

func (a *API) logRequestFailure(
	r *http.Request,
	message string,
	status int,
	started time.Time,
	extra ...any,
) {
	fields := []any{
		"request_id", requestIDFromContext(r.Context()),
		"method", r.Method,
		"route", requestRoute(r),
		"status", status,
		"duration_ms", time.Since(started).Milliseconds(),
	}
	fields = append(fields, extra...)
	a.logger.ErrorContext(r.Context(), message, fields...)
}

func requestRoute(r *http.Request) string {
	if r.Pattern == "" {
		return "unmatched"
	}
	return r.Pattern
}

func requestIDFromContext(ctx context.Context) string {
	requestID, _ := ctx.Value(requestIDContextKey{}).(string)
	return requestID
}

func validRequestID(raw string) string {
	requestID := strings.TrimSpace(raw)
	if requestID == "" || len(requestID) > maximumRequestIDSize {
		return ""
	}
	for _, character := range requestID {
		if (character >= 'a' && character <= 'z') ||
			(character >= 'A' && character <= 'Z') ||
			(character >= '0' && character <= '9') ||
			strings.ContainsRune("._:-", character) {
			continue
		}
		return ""
	}
	return requestID
}

func newRequestID() string {
	var random [16]byte
	if _, err := rand.Read(random[:]); err == nil {
		return hex.EncodeToString(random[:])
	}
	return fmt.Sprintf(
		"fallback-%d-%d",
		time.Now().UnixNano(),
		requestIDFallback.Add(1),
	)
}

func decodeBody(w http.ResponseWriter, r *http.Request, maximum int64, target any) error {
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || !strings.EqualFold(mediaType, "application/json") {
		return errUnsupportedMediaType
	}
	r.Body = http.MaxBytesReader(w, r.Body, maximum)
	encoded, err := io.ReadAll(r.Body)
	if err != nil {
		return err
	}
	if !utf8.Valid(encoded) {
		return errors.New("request body is not valid UTF-8")
	}
	if err := validateUniqueJSONFields(encoded); err != nil {
		return err
	}
	var shape any
	shapeDecoder := json.NewDecoder(bytes.NewReader(encoded))
	shapeDecoder.UseNumber()
	if err := shapeDecoder.Decode(&shape); err != nil {
		return err
	}
	if err := validateExactJSONFields(shape, reflect.TypeOf(target)); err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("request body must contain one JSON value")
		}
		return err
	}
	return nil
}

func validateUniqueJSONFields(encoded []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.UseNumber()
	if err := scanUniqueJSONValue(decoder); err != nil {
		return err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("request body must contain one JSON value")
		}
		return err
	}
	return nil
}

func scanUniqueJSONValue(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, compound := token.(json.Delim)
	if !compound {
		return nil
	}
	switch delimiter {
	case '{':
		seen := make(map[string]bool)
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok {
				return errors.New("JSON object key is not a string")
			}
			if seen[key] {
				return fmt.Errorf("json: duplicate field %q", key)
			}
			seen[key] = true
			if err := scanUniqueJSONValue(decoder); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim('}') {
			return errors.New("JSON object was not closed")
		}
	case '[':
		for decoder.More() {
			if err := scanUniqueJSONValue(decoder); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim(']') {
			return errors.New("JSON array was not closed")
		}
	default:
		return fmt.Errorf("unexpected JSON delimiter %q", delimiter)
	}
	return nil
}

var rawMessageType = reflect.TypeOf(json.RawMessage{})

func validateExactJSONFields(value any, target reflect.Type) error {
	for target.Kind() == reflect.Pointer {
		target = target.Elem()
	}
	if target == rawMessageType || target.Kind() == reflect.Interface {
		return nil
	}
	switch target.Kind() {
	case reflect.Struct:
		object, ok := value.(map[string]any)
		if !ok {
			return nil
		}
		fields := make(map[string]reflect.Type)
		for index := 0; index < target.NumField(); index++ {
			field := target.Field(index)
			if field.PkgPath != "" {
				continue
			}
			name := field.Name
			if tag, exists := field.Tag.Lookup("json"); exists {
				name = strings.Split(tag, ",")[0]
				if name == "-" {
					continue
				}
				if name == "" {
					name = field.Name
				}
			}
			fields[name] = field.Type
		}
		for name, nested := range object {
			fieldType, found := fields[name]
			if !found {
				return fmt.Errorf("json: unknown field %q", name)
			}
			if err := validateExactJSONFields(nested, fieldType); err != nil {
				return err
			}
		}
	case reflect.Slice, reflect.Array:
		if target == rawMessageType {
			return nil
		}
		array, ok := value.([]any)
		if !ok {
			return nil
		}
		for _, nested := range array {
			if err := validateExactJSONFields(nested, target.Elem()); err != nil {
				return err
			}
		}
	case reflect.Map:
		object, ok := value.(map[string]any)
		if !ok {
			return nil
		}
		for _, nested := range object {
			if err := validateExactJSONFields(nested, target.Elem()); err != nil {
				return err
			}
		}
	}
	return nil
}

func writeDecodeError(w http.ResponseWriter, err error) {
	if errors.Is(err, errUnsupportedMediaType) {
		writeError(w, http.StatusUnsupportedMediaType, "unsupported_media_type", err.Error())
		return
	}
	var maxBytesErr *http.MaxBytesError
	if errors.As(err, &maxBytesErr) {
		writeError(w, http.StatusRequestEntityTooLarge, "request_too_large", "request body is too large")
		return
	}
	writeError(w, http.StatusBadRequest, "invalid_json", "request body is not valid: "+err.Error())
}

func queryBool(r *http.Request, name string) (bool, error) {
	raw := strings.TrimSpace(r.URL.Query().Get(name))
	if raw == "" {
		return false, nil
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("%s must be a boolean", name)
	}
	return value, nil
}

func queryPage(r *http.Request) (int, string, error) {
	limit := store.DefaultPageLimit
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > store.MaximumPageLimit {
			return 0, "", fmt.Errorf("limit must be between 1 and %d", store.MaximumPageLimit)
		}
		limit = parsed
	}
	return limit, strings.TrimSpace(r.URL.Query().Get("cursor")), nil
}

func bearerToken(header string) string {
	parts := strings.Fields(header)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return parts[1]
}

func isLoopbackRequest(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	address := net.ParseIP(strings.Trim(host, "[]"))
	return address != nil && address.IsLoopback()
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeBoundedJSON(w http.ResponseWriter, status int, value any) {
	encoded, err := json.Marshal(value)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "the response could not be encoded")
		return
	}
	if len(encoded)+1 > store.MaximumJSONResponseBytes {
		writeError(w, http.StatusUnprocessableEntity, "response_too_large", "the response exceeds the documented size limit")
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(append(encoded, '\n'))
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}

// ShutdownContext provides a bounded context shared by the command entrypoint.
func ShutdownContext(parent context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, 10*time.Second)
}
