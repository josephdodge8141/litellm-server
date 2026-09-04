FROM ghcr.io/berriai/litellm:main-latest

# Config is mounted at /app/config.yaml via docker-compose or --config flag
# No additional dependencies needed for Bedrock (boto3 is baked in).
# Copy config for standalone docker run (compose overrides via volume)
COPY config.yaml /app/config.yaml

EXPOSE 4000
# Entrypoint is already `litellm` in base image
# Default command uses the bundled config
CMD ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "4"]
