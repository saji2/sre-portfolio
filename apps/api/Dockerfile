# Build stage
FROM golang:1.24-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-w -s -extldflags "-static"' \
    -o /app/server ./cmd/server

# Runtime stage
FROM alpine:3.21

# Install wget for healthcheck and ca-certificates
RUN apk add --no-cache ca-certificates tzdata wget

# Copy binary
COPY --from=builder /app/server /server

# Copy migrations
COPY --from=builder /app/migrations /migrations

# Non-root user
RUN adduser -D -u 1000 appuser
USER appuser

EXPOSE 8080

ENTRYPOINT ["/server"]
