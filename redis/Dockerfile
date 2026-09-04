FROM redis:7-alpine
# Tiny wrapper so compose uses `build:` as requested for all services.
# Inherits redis.conf defaults; persistence via volume, healthcheck via compose.
# No custom config needed for local scale — append-only + maxmemory handled upstream if needed.
EXPOSE 6379
