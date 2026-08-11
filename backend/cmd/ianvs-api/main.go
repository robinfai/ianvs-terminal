package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/httpapi"
	"ianvs-terminal/backend/internal/legacy"
	"ianvs-terminal/backend/internal/secure"
	"ianvs-terminal/backend/internal/store"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		log.Printf("error: %v", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	command := "serve"
	if len(args) > 0 {
		command = args[0]
		args = args[1:]
	}
	if command == "generate-key" {
		key, err := secure.GenerateUserKey()
		if err != nil {
			return err
		}
		fmt.Println(key)
		return nil
	}

	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	db, err := database.Open(cfg)
	if err != nil {
		return err
	}
	resourceStore, err := store.New(context.Background(), db)
	if err != nil {
		return err
	}
	authService := auth.New(db, cfg.TokenTTL)
	if cfg.Mode == config.ModeLocal {
		if _, err := authService.EnsureLocalUser(context.Background()); err != nil {
			return err
		}
	}

	switch command {
	case "serve":
		if len(args) != 0 {
			return errors.New("serve does not accept positional arguments")
		}
		return serve(cfg, authService, resourceStore)
	case "import-legacy":
		return importLegacy(cfg, authService, resourceStore, args)
	default:
		return fmt.Errorf("unknown command %q (expected serve, import-legacy, or generate-key)", command)
	}
}

func serve(cfg config.Config, authService *auth.Service, resourceStore *store.Store) error {
	api := httpapi.New(cfg, authService, resourceStore)
	server := &http.Server{
		Addr:              cfg.Address,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       45 * time.Second,
		WriteTimeout:      45 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	serverError := make(chan error, 1)
	listener, err := net.Listen("tcp", cfg.Address)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", cfg.Address, err)
	}
	readyURL := "http://" + listener.Addr().String()
	if _, err := fmt.Fprintf(os.Stdout, "IANVS_API_READY=%s\n", readyURL); err != nil {
		_ = listener.Close()
		return fmt.Errorf("announce API readiness: %w", err)
	}
	go func() {
		log.Printf(
			"ianvs data API listening on %s (mode=%s, database=%s, server_id=%s)",
			listener.Addr().String(),
			cfg.Mode,
			cfg.DatabaseDriver,
			resourceStore.ServerID(),
		)
		serverError <- server.Serve(listener)
	}()

	signalContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	var stdinClosed <-chan struct{}
	if cfg.ExitOnStdinClose {
		closed := make(chan struct{})
		stdinClosed = closed
		go func() {
			_, _ = io.Copy(io.Discard, os.Stdin)
			close(closed)
		}()
	}
	select {
	case <-signalContext.Done():
	case <-stdinClosed:
		log.Printf("parent input closed; stopping local data API")
	case err := <-serverError:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return fmt.Errorf("serve HTTP: %w", err)
	}

	shutdownContext, cancel := httpapi.ShutdownContext(context.Background())
	defer cancel()
	if err := server.Shutdown(shutdownContext); err != nil {
		return fmt.Errorf("shutdown server: %w", err)
	}
	return nil
}

func importLegacy(
	cfg config.Config,
	authService *auth.Service,
	resourceStore *store.Store,
	args []string,
) error {
	if cfg.Mode != config.ModeLocal {
		return errors.New("import-legacy is available only when IANVS_API_MODE=local")
	}
	flags := flag.NewFlagSet("import-legacy", flag.ContinueOnError)
	directory := flags.String("dir", cfg.LegacyDirectory, "application support directory containing legacy JSON files")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("import-legacy accepts only the --dir option")
	}
	if cfg.EncryptionKey == "" {
		return errors.New("IANVS_ENCRYPTION_KEY is required for legacy import")
	}
	user, _, err := authService.SetupLocalKey(context.Background(), cfg.EncryptionKey)
	if err != nil {
		return err
	}
	key, err := authService.VerifyKey(user, cfg.EncryptionKey)
	if err != nil {
		return err
	}
	importer, err := legacy.New(resourceStore, cfg.LegacyProfileKey)
	if err != nil {
		return err
	}
	report, err := importer.Import(
		context.Background(),
		user,
		key,
		*directory,
	)
	if err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return fmt.Errorf("encode import report: %w", err)
	}
	fmt.Println(string(encoded))
	return nil
}
