# litellm-server

Local LiteLLM proxy backed by AWS Bedrock. One container, ~195 model aliases, OpenAI-compatible API on `http://localhost:4000`.

```
curl / apps ──► http://localhost:4000/v1/chat/completions  (OpenAI spec)
                  │
                  ▼
              litellm proxy (ghcr.io/berriai/litellm)
                  │  AWS_BEARER_TOKEN_BEDROCK
                  ▼
              AWS Bedrock (us-east-1)  ── 122 foundation models + 73 inference profiles
```

## Model coverage

`config.yaml` is generated from `bedrock list-foundation-models` + `list-inference-profiles` (us-east-1, 2026-09-03). 195 entries total:

| Group | Count | Examples |
|-------|-------|----------|
| Chat / Converse (TEXT→TEXT) | 89 | `anthropic-claude-sonnet-4-20250514-v1-0`, `openai-gpt-oss-120b-1-0`, `meta-llama3-3-70b-instruct-v1-0` |
| Inference Profiles (cross-region & global) | 73 | `us-anthropic-claude-sonnet-4-5-20250929-v1-0`, `global-openai-gpt-5-6-terra` |
| Embeddings | 15 | `amazon-titan-embed-text-v2-0`, `cohere-embed-english-v3` |
| Image / Video | 16 | `stability-stable-image-control-structure-v1-0`, `amazon-nova-reel-v1-0` |
| Other (speech etc) | 2 | `amazon-nova-2-sonic-v1-0` |

Aliases are `modelId` with `.` and `:` → `-` (e.g. `anthropic.claude-sonnet-4-20250514-v1:0` → `anthropic-claude-sonnet-4-20250514-v1-0`). The underlying `litellm_params.model` is always `bedrock/<original-id>` so LiteLLM routes correctly.

> For Anthropic and OpenAI in production prefer the `us.*` or `global.*` inference-profile aliases — they give cross-region failover and higher quotas.

## Prerequisites

- Docker Desktop (or `docker` + `docker compose`)
- AWS Bedrock access in `us-east-1`. This repo is wired to the Bedrock API key created for IAM user `litellm-bedrock`:

```bash
aws iam create-user --user-name litellm-bedrock
aws iam attach-user-policy --user-name litellm-bedrock --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
aws iam create-service-specific-credential --user-name litellm-bedrock --service-name bedrock.amazonaws.com --credential-age-days 365
# → ServiceCredentialSecret is your AWS_BEARER_TOKEN_BEDROCK
```

A $20/month AWS Budget `litellm-bedrock-20usd` scoped to `Service=Amazon Bedrock` with 80%/100% actual + 100% forecasted alerts to `joe.dodge@nice.com` is already configured.

## Quick start

```bash
# 1. Configure env
cp .env.example .env
# edit .env → set LITELLM_MASTER_KEY and AWS_BEARER_TOKEN_BEDROCK

# 2. Start
docker compose up -d --build

# 3. Health check
curl -s http://localhost:4000/health/liveliness -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# 4. List models
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq '.data[].id' | head

# 5. Chat (OpenAI-compatible)
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic-claude-sonnet-4-20250514-v1-0",
    "messages": [{"role": "user", "content": "Hello from litellm!"}]
  }' | jq .

# 6. Cross-region alias (recommended)
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "us-anthropic-claude-sonnet-4-5-20250929-v1-0",
    "messages": [{"role": "user", "content": "Use the inference profile."}]
  }' | jq .
```

For IAM access keys instead of bearer token, set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in `.env` and leave `AWS_BEARER_TOKEN_BEDROCK` empty.

## Configuration

- `config.yaml` — model list + `litellm_settings` + `general_settings.master_key = os.environ/LITELLM_MASTER_KEY`. Regenerate with `scripts/refresh-config.sh`.
- `Dockerfile` — `FROM ghcr.io/berriai/litellm:main-latest`, bakes `config.yaml`, runs `--config /app/config.yaml --port 4000`.
- `docker-compose.yml` — mounts `config.yaml` ro, loads `.env`, exposes `4000`, healthcheck on `/health/liveliness`.

## Refreshing the model catalog

Bedrock adds models frequently. Refresh without hand-editing:

```bash
./scripts/refresh-config.sh   # re-calls list-foundation-models + list-inference-profiles and rewrites config.yaml
docker compose up -d --build
```

## Not-So-Localhost (optional)

Expose the proxy on your tailnet:

```bash
nsl add --name litellm --target-url http://host.docker.internal:4000
# → https://litellm--<node>.joedodge.dev
# Use `upstream` auth policy if clients send their own Bearer tokens.
```

## Security notes

- Never commit `.env`. The Bedrock API key (`ABSK...`) is a service-specific credential for user `litellm-bedrock` expiring 2027-09-04. Rotate with `create-service-specific-credential`.
- `LITELLM_MASTER_KEY` is the only key clients need; Bedrock credentials stay server-side.
- All models require `AWS_REGION=us-east-1` unless you reconfigure `config.yaml`.

