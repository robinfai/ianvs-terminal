package main

import (
	"context"
	"errors"
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
	if len(args) == 0 {
		return errors.New("a command is required (serve or generate-key)")
	}
	command := args[0]
	args = args[1:]
	if command == "generate-key" {
		if len(args) != 0 {
			return errors.New("generate-key does not accept arguments")
		}
		key, err := secure.GenerateUserKey()
		if err != nil {
			return err
		}
		fmt.Println(key)
		return nil
	}

	if command != "serve" {
		return fmt.Errorf("unknown command %q (expected serve or generate-key)", command)
	}
	if len(args) != 2 || args[0] != "--config" || args[1] == "" {
		return errors.New("serve requires exactly --config <path>")
	}
	cfg, err := config.Load(args[1])
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

	return serve(cfg, authService, resourceStore)
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
