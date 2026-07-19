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
MAXLEN=$(jq -r '.env.MAX_MODEL_LEN' "$CFG")
GPUMEM=$(jq -r '.env.GPU_MEMORY_UTILIZATION' "$CFG")

echo ">>> creating template ${NAME}-template" >&2
TMPL=$(jq -n --arg name "${NAME}-template" --arg img "$IMAGE" \
  --arg model "$MODEL" --arg maxlen "$MAXLEN" --arg gpumem "$GPUMEM" --arg hf "$HF_TOKEN" \
  '{name:$name, imageName:$img, isServerless:true, containerDiskInGb:60,
    env:{MODEL_NAME:$model, MAX_MODEL_LEN:$maxlen, GPU_MEMORY_UTILIZATION:$gpumem, HF_TOKEN:$hf}}' \
  | curl -sS -X POST "$API/templates" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d @-)
TMPL_ID=$(echo "$TMPL" | jq -r '.id // empty')
[ -n "$TMPL_ID" ] || { echo "template create failed: $TMPL" >&2; exit 1; }
echo ">>> template id: $TMPL_ID" >&2

echo ">>> creating serverless endpoint ${NAME}" >&2
EP=$(jq -n --arg name "$NAME" --arg tmpl "$TMPL_ID" \
  '{name:$name, templateId:$tmpl, computeType:"GPU",
    gpuTypeIds:["NVIDIA GeForce RTX 3090","NVIDIA RTX A5000","NVIDIA L4"],
    gpuCount:1, workersMax:2, workersMin:0}' \
  | curl -sS -X POST "$API/endpoints" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d @-)
EP_ID=$(echo "$EP" | jq -r '.id // empty')
[ -n "$EP_ID" ] || { echo "endpoint create failed: $EP" >&2; exit 1; }

echo ""
echo "endpoint id:  $EP_ID"
echo "LLM_ENDPOINT: https://api.runpod.ai/v2/$EP_ID/"
echo ""
echo "Verify (first call pulls the ~18GB model — takes minutes):"
echo "  curl -sS https://api.runpod.ai/v2/$EP_ID/openai/v1/chat/completions -H \"Authorization: Bearer \$RUNPOD_API_KEY\" -H 'Content-Type: application/json' -d '{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the word ready.\"}]}'"
