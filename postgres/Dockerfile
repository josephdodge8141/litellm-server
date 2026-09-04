FROM postgres:16-alpine

# LiteLLM requires a persistent Postgres for UI users, keys, and spend logs.
# All runtime config comes from docker-compose environment (POSTGRES_*).
# This Dockerfile exists so compose uses `build:` as requested (not just `image:`).
# No custom init needed; base entrypoint handles DB creation.

HEALTHCHECK --interval=5s --timeout=5s --retries=10 \
  CMD pg_isready -U ${POSTGRES_USER:-litellm} -d ${POSTGRES_DB:-litellm} || exit 1

EXPOSE 5432
