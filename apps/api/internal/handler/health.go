package handler

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sre-portfolio/api/internal/cache"
)

type HealthHandler struct {
	db    *sql.DB
	redis *cache.RedisClient
}

func NewHealthHandler(db *sql.DB, redis *cache.RedisClient) *HealthHandler {
	if db == nil {
		log.Println("Warning: HealthHandler created with nil database connection")
	}
	if redis == nil {
		log.Println("Warning: HealthHandler created with nil redis client")
	}
	return &HealthHandler{
		db:    db,
		redis: redis,
	}
}

func (h *HealthHandler) Liveness(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
	})
}

func (h *HealthHandler) Readiness(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "unhealthy",
			"database": "unavailable",
		})
		return
	}

	if err := h.db.PingContext(ctx); err != nil {
		log.Printf("Database health check failed: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "unhealthy",
			"database": "unavailable",
		})
		return
	}

	if h.redis == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "unhealthy",
			"database": "ok",
			"redis":    "unavailable",
		})
		return
	}

	if err := h.redis.Ping(ctx); err != nil {
		log.Printf("Redis health check failed: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "unhealthy",
			"database": "ok",
			"redis":    "unavailable",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":   "ok",
		"database": "ok",
		"redis":    "ok",
	})
}
