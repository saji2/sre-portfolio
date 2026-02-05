package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/sre-portfolio/api/internal/cache"
	"github.com/sre-portfolio/api/internal/config"
	"github.com/sre-portfolio/api/internal/handler"
	"github.com/sre-portfolio/api/internal/middleware"
	"github.com/sre-portfolio/api/internal/repository"
	"github.com/sre-portfolio/api/internal/service"
)

func main() {
	cfg := config.Load()

	gin.SetMode(cfg.Server.Mode)

	db, err := repository.NewDB(cfg.Database)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	redis, err := cache.NewRedis(cfg.Redis)
	if err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	defer redis.Close()

	userRepo := repository.NewUserRepository(db)
	taskRepo := repository.NewTaskRepository(db)

	authService := service.NewAuthService(userRepo, redis, cfg.JWT)
	taskService := service.NewTaskService(taskRepo)

	authHandler := handler.NewAuthHandler(authService)
	taskHandler := handler.NewTaskHandler(taskService)
	healthHandler := handler.NewHealthHandler(db, redis)

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(middleware.Logger())
	r.Use(middleware.CORS(cfg.CORS))
	r.Use(middleware.Metrics())

	r.GET("/health/live", healthHandler.Liveness)
	r.GET("/health/ready", healthHandler.Readiness)
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	v1 := r.Group("/api/v1")
	{
		auth := v1.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/refresh", authHandler.Refresh)
		}

		protected := v1.Group("")
		protected.Use(middleware.Auth(authService))
		{
			protected.POST("/auth/logout", authHandler.Logout)

			tasks := protected.Group("/tasks")
			{
				tasks.GET("", taskHandler.List)
				tasks.GET("/:id", taskHandler.Get)
				tasks.POST("", taskHandler.Create)
				tasks.PUT("/:id", taskHandler.Update)
				tasks.DELETE("/:id", taskHandler.Delete)
				tasks.PATCH("/:id/status", taskHandler.UpdateStatus)
			}
		}
	}

	port := cfg.Server.Port
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		log.Printf("Server starting on port %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal for graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	// Create context with timeout for shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited gracefully")
}
