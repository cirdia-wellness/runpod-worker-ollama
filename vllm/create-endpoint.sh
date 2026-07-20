#!/usr/bin/env bash
# Create the vLLM serverless endpoint from vllm/endpoint.dev.json (issue #1).
# Run from the repo root IN YOUR OWN TERMINAL. Requires:
#   RUNPOD_API_KEY (or LLM_AUTH_TOKEN) exported — the RunPod API key
#   HF_TOKEN exported — Hugging Face token (accept the model's terms first)
# Prints the endpoint id + base URL on success. Idempotent-ish: fails loudly
# if a template/endpoint with the same name already exists — delete in the
# console (or via the API) before re-running.
set -euo pipefail

KEY="${RUNPOD_API_KEY:-${LLM_AUTH_TOKEN:-}}"
: "${KEY:?export RUNPOD_API_KEY (or LLM_AUTH_TOKEN) first}"
: "${HF_TOKEN:?export HF_TOKEN first (huggingface.co -> accept model terms -> Settings -> Access Tokens)}"
API="https://rest.runpod.io/v1"
CFG="$(dirname "$0")/endpoint.dev.json"

NAME=$(jq -r '.name' "$CFG")
IMAGE=$(jq -r '.image' "$CFG")
MODEL=$(jq -r '.env.MODEL_NAME' "$CFG")

echo ">>> creating template ${NAME}-template" >&2
# Every value comes from the config file — the file is the source of truth
# (#1). HF_TOKEN's placeholder is replaced from the operator's environment
# (never stored in the file).
TMPL=$(jq --arg name "${NAME}-template" --arg hf "$HF_TOKEN" \
  '{name:$name, imageName:.image, isServerless:true,
    containerDiskInGb:(.container_disk_gb // 60),
    env:(.env + {HF_TOKEN:$hf})}' "$CFG" \
  | curl -sS -X POST "$API/templates" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d @-)
TMPL_ID=$(echo "$TMPL" | jq -r '.id // empty')
[ -n "$TMPL_ID" ] || { echo "template create failed: $TMPL" >&2; exit 1; }
echo ">>> template id: $TMPL_ID" >&2

echo ">>> creating serverless endpoint ${NAME}" >&2
EP=$(jq --arg tmpl "$TMPL_ID" \
  '{name:.name, templateId:$tmpl, computeType:"GPU",
    gpuTypeIds:.gpu_type_ids, gpuCount:1,
    workersMax:(.workers_max // 2), workersMin:(.workers_active // 0)}' "$CFG" \
  | curl -sS -X POST "$API/endpoints" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d @-)
EP_ID=$(echo "$EP" | jq -r '.id // empty')
[ -n "$EP_ID" ] || { echo "endpoint create failed: $EP" >&2; exit 1; }

# Verify what RunPod actually stored — its API has translated explicit card
# lists into whole GPU tiers before (which is how MIG slices snuck in). Fail
# loudly on any mismatch instead of discovering it at the first OOM.
STORED=$(curl -sS "$API/endpoints/$EP_ID" -H "Authorization: Bearer $KEY" | jq -c '.gpuTypeIds | sort')
WANTED=$(jq -c '.gpu_type_ids | sort' "$CFG")
if [ "$STORED" != "$WANTED" ]; then
  echo "ERROR: RunPod stored gpuTypeIds $STORED but config wants $WANTED" >&2
  echo "       Fix via: curl -X PATCH $API/endpoints/$EP_ID with the exact list, then re-verify." >&2
  exit 1
fi
echo ">>> gpuTypeIds verified: $STORED" >&2

echo ""
echo "endpoint id:  $EP_ID"
echo "LLM_ENDPOINT: https://api.runpod.ai/v2/$EP_ID/"
echo ""
echo "Verify (first call pulls the ~18GB model — takes minutes):"
echo "  curl -sS https://api.runpod.ai/v2/$EP_ID/openai/v1/chat/completions -H \"Authorization: Bearer \$RUNPOD_API_KEY\" -H 'Content-Type: application/json' -d '{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the word ready.\"}]}'"
