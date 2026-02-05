package config

import (
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	JWT      JWTConfig
	CORS     CORSConfig
}

type ServerConfig struct {
	Port string
	Mode string
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

type RedisConfig struct {
	Host       string
	Port       string
	Password   string
	DB         int
	TLSEnabled bool
}

type JWTConfig struct {
	Secret           string
	AccessExpiresIn  time.Duration
	RefreshExpiresIn time.Duration
}

type CORSConfig struct {
	AllowedOrigins []string
}

func Load() *Config {
	mode := getEnv("GIN_MODE", "debug")
	corsOrigins := parseCORSOrigins(getEnv("CORS_ALLOWED_ORIGINS", "*"))

	// Warn if CORS allows all origins in production
	if mode == "release" && len(corsOrigins) > 0 && corsOrigins[0] == "*" {
		log.Println("Warning: CORS allows all origins in production, consider restricting CORS_ALLOWED_ORIGINS")
	}

	return &Config{
		Server: ServerConfig{
			Port: getEnv("PORT", "8080"),
			Mode: mode,
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "postgres"),
			DBName:   getEnv("DB_NAME", "taskmanager"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		Redis: RedisConfig{
			Host:       getEnv("REDIS_HOST", "localhost"),
			Port:       getEnv("REDIS_PORT", "6379"),
			Password:   getEnv("REDIS_PASSWORD", ""),
			DB:         getEnvInt("REDIS_DB", 0),
			TLSEnabled: getEnvBool("REDIS_TLS_ENABLED", false),
		},
		JWT: JWTConfig{
			Secret:           getJWTSecret(),
			AccessExpiresIn:  time.Duration(getEnvInt("JWT_ACCESS_EXPIRES_MINUTES", 15)) * time.Minute,
			RefreshExpiresIn: time.Duration(getEnvInt("JWT_REFRESH_EXPIRES_DAYS", 7)) * 24 * time.Hour,
		},
		CORS: CORSConfig{
			AllowedOrigins: corsOrigins,
		},
	}
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		intValue, err := strconv.Atoi(value)
		if err != nil {
			log.Printf("Warning: invalid integer value for %s: %s, using default %d", key, value, defaultValue)
			return defaultValue
		}
		return intValue
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value, exists := os.LookupEnv(key); exists {
		boolValue, err := strconv.ParseBool(value)
		if err != nil {
			log.Printf("Warning: invalid boolean value for %s: %s, using default %v", key, value, defaultValue)
			return defaultValue
		}
		return boolValue
	}
	return defaultValue
}

func getJWTSecret() string {
	const defaultSecret = "default-secret-change-in-production"
	secret := getEnv("JWT_SECRET", defaultSecret)
	env := getEnv("GIN_MODE", "debug")

	if env == "release" && (secret == "" || secret == defaultSecret) {
		log.Fatal("FATAL: JWT_SECRET must be set in production environment")
	}

	if secret == defaultSecret {
		log.Println("Warning: using default JWT secret, this is insecure for production")
	}

	return secret
}

func parseCORSOrigins(value string) []string {
	if value == "" {
		return []string{"*"}
	}

	parts := strings.Split(value, ",")
	origins := make([]string, 0, len(parts))
	for _, p := range parts {
		trimmed := strings.TrimSpace(p)
		if trimmed != "" {
			origins = append(origins, trimmed)
		}
	}

	if len(origins) == 0 {
		return []string{"*"}
	}
	return origins
}
