package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/sre-portfolio/api/internal/config"
)

func CORS(cfg config.CORSConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		var allowedOrigin string
		var isWildcard bool
		for _, allowed := range cfg.AllowedOrigins {
			if allowed == "*" {
				allowedOrigin = "*"
				isWildcard = true
				break
			}
			if allowed == origin {
				allowedOrigin = origin
				break
			}
		}

		if allowedOrigin == "" {
			c.Next()
			return
		}

		c.Writer.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")
		c.Writer.Header().Set("Access-Control-Max-Age", "86400")
		c.Writer.Header().Add("Vary", "Origin")

		if !isWildcard {
			c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		}

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}
