#!/usr/bin/env bash
set -euo pipefail
# Regenerate config.yaml from live Bedrock catalog (us-east-1)
PROFILE="${AWS_PROFILE:-mine}"
REGION="${AWS_REGION:-us-east-1}"
OUT="${1:-config.yaml}"
TMP_PY=$(mktemp /tmp/gen-XXXX.py)

cat > "$TMP_PY" << 'PY'
import json, subprocess, os

profile = os.environ.get("AWS_PROFILE", "mine")
region = os.environ.get("AWS_REGION", "us-east-1")

models_raw = subprocess.check_output(
    f"env -u AWS_BEARER_TOKEN_BEDROCK aws --profile {profile} bedrock list-foundation-models --region {region} --output json",
    shell=True
)
models = json.loads(models_raw)["modelSummaries"]

profiles_raw = subprocess.check_output(
    f"env -u AWS_BEARER_TOKEN_BEDROCK aws --profile {profile} bedrock list-inference-profiles --region {region} --output json",
    shell=True
)
profiles = json.loads(profiles_raw)["inferenceProfileSummaries"]

def is_chat(m):
    return "TEXT" in m["inputModalities"] and "TEXT" in m["outputModalities"]
def is_embed(m):
    return "EMBEDDING" in m["outputModalities"]
def is_image(m):
    return "IMAGE" in m["outputModalities"] and "TEXT" not in m["outputModalities"]

chat = [m for m in models if is_chat(m)]
embed = [m for m in models if not is_chat(m) and is_embed(m)]
image = [m for m in models if not is_chat(m) and not is_embed(m) and is_image(m)]
video = [m for m in models if "VIDEO" in m["outputModalities"]]
other = [m for m in models if m not in chat+embed+image+video]

def alias_for(mid):
    return mid.replace(".", "-").replace(":", "-").replace("/", "-")

lines = []
lines.append("model_list:")
lines.append("  # ── Chat / Converse (TEXT→TEXT) ──")
for m in sorted(chat, key=lambda x: (x["providerName"], x["modelId"])):
    mid = m["modelId"]
    lines.append(f"  - model_name: {alias_for(mid)}")
    lines.append(f"    litellm_params:")
    lines.append(f"      model: bedrock/{mid}")
    lines.append(f"      aws_region_name: us-east-1")
lines.append("")
lines.append("  # ── Cross-Region / Global Inference Profiles ──")
for p in sorted(profiles, key=lambda x: x["inferenceProfileId"]):
    pid = p["inferenceProfileId"]
    lines.append(f"  - model_name: {alias_for(pid)}")
    lines.append(f"    litellm_params:")
    lines.append(f"      model: bedrock/{pid}")
    lines.append(f"      aws_region_name: us-east-1")
lines.append("")
lines.append("  # ── Embeddings ──")
for m in sorted(embed, key=lambda x: x["modelId"]):
    mid = m["modelId"]
    lines.append(f"  - model_name: {alias_for(mid)}")
    lines.append(f"    litellm_params:")
    lines.append(f"      model: bedrock/{mid}")
    lines.append(f"      aws_region_name: us-east-1")
lines.append("")
lines.append("  # ── Image / Video Generation ──")
for m in sorted(image+video, key=lambda x: x["modelId"]):
    mid = m["modelId"]
    lines.append(f"  - model_name: {alias_for(mid)}")
    lines.append(f"    litellm_params:")
    lines.append(f"      model: bedrock/{mid}")
    lines.append(f"      aws_region_name: us-east-1")
if other:
    lines.append("")
    lines.append("  # ── Other ──")
    for m in sorted(other, key=lambda x: x["modelId"]):
        mid = m["modelId"]
        lines.append(f"  - model_name: {alias_for(mid)}")
        lines.append(f"    litellm_params:")
        lines.append(f"      model: bedrock/{mid}")
        lines.append(f"      aws_region_name: us-east-1")
lines.append("")
lines.append("litellm_settings:")
lines.append("  num_retries: 2")
lines.append("  request_timeout: 600")
lines.append("  set_verbose: false")
lines.append("  drop_params: true")
lines.append("")
lines.append("general_settings:")
lines.append("  master_key: os.environ/LITELLM_MASTER_KEY")
lines.append("")

open(os.environ.get("OUT_PATH", "config.yaml"), "w").write("\n".join(lines))
print(f"Wrote {len(lines)} lines to {os.environ.get('OUT_PATH', 'config.yaml')}  ({len(chat)} chat + {len(profiles)} profiles + {len(embed)} embed + {len(image)+len(video)} image/video)")
PY

OUT_PATH="$OUT" AWS_PROFILE="$PROFILE" AWS_REGION="$REGION" python3 "$TMP_PY"
rm "$TMP_PY"
echo "Done → $OUT"
