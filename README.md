# Cirdia LLM Endpoint — vLLM serving for the insight engine

*Who reads this: whoever creates, changes, or retires the LLM serving endpoints the PIE worker calls. The engine-side contract lives in `ephemeral-instance` (issue #39); this repo owns what the endpoint **is**.*

## What this is

The insight engine's LLM endpoint runs **vLLM** (RunPod's official serverless worker image) serving the **original Apache-2.0 weights** of `mistralai/Ministral-3-8B-Instruct-2512`, with **server-enforced structured output** (`response_format: json_schema`).

Why vLLM and original weights: the previous Ollama-based endpoint served a quantized copy that ignored editorial instructions — no correlation findings, clinical/advice leakage, broken formatting (issue #1). A control run of identical prompts against strict-enforcement serving of original weights produced the designed report. Self-hosting is a PIE invariant — no third-party inference APIs, ever.

**Licensing:** Ministral 3 (2512) is Apache 2.0 — commercially usable. Do **not** substitute `Ministral-8B-Instruct-2410`; it is Mistral Research License (non-commercial).

## Endpoint definition

Source of truth per environment: [`vllm/endpoint.dev.json`](vllm/endpoint.dev.json) and [`vllm/endpoint.prod.json`](vllm/endpoint.prod.json). **They differ deliberately:** prod sets `DISABLE_LOG_REQUESTS=True` (privacy-load-bearing — vLLM would otherwise log full request bodies, i.e. decrypted member data, into RunPod's persistent logs); dev keeps logging on because it carries synthetic test data only. Never copy dev's logging posture to prod.

**Keys:** the endpoint is *created* with the account API key; the engine's workers *call* it with a **restricted, endpoint-invocation-only** RunPod key (`LLM_AUTH_TOKEN_WORKER` in the engine deploy) — a compromised ephemeral worker must not hold account control.

## Creating the dev endpoint

Scripted (preferred — reads `endpoint.dev.json`, prints the endpoint id and `LLM_ENDPOINT` URL):

```bash
export HF_TOKEN=<hugging face read token>   # RUNPOD_API_KEY or LLM_AUTH_TOKEN already exported
./vllm/create-endpoint.sh
```

Or by console:

1. **Serverless → New Endpoint → Docker image** → `runpod/worker-v1-vllm:stable-cuda12.1.0`
2. Name: `vllm-ministral-dev` · GPU: **24GB tier** · Max workers 2, active 0 · Container disk 60GB
3. Environment variables — exactly the `env` block from `vllm/endpoint.dev.json`, with `HF_TOKEN` supplied from your secret store (never written into the file)
4. Deploy. First request triggers the model download (~18GB) — several minutes, once per fresh worker

## Verifying it works

```bash
curl -sS https://api.runpod.ai/v2/<ENDPOINT_ID>/openai/v1/chat/completions \
  -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"mistralai/Ministral-3-8B-Instruct-2512","messages":[{"role":"user","content":"Reply with the word ready."}]}'
```

A `choices[0].message.content` reply = live. The engine's prompt-eval harness (`ephemeral-instance/testing/`) is the real acceptance test — see issue #1's criteria.

## Request surface (what the engine calls)

- `POST https://api.runpod.ai/v2/<ENDPOINT_ID>/openai/v1/chat/completions`
- Auth: `Bearer <RUNPOD_API_KEY>` · Body: OpenAI chat-completions, including `response_format: {type: "json_schema", ...}` for enforced structured output
- Synchronous — no runsync/status polling

## Legacy — Ollama worker (being retired)

Everything outside `vllm/` (Dockerfile, `src/`, `embed_model/`, `test_inputs/`) is the previous Ollama serverless worker, forked from [svenbrnn/runpod-worker-ollama](https://github.com/svenbrnn/runpod-worker-ollama) (CC BY 4.0 — attribution retained). The Ollama endpoint stays up until the vLLM endpoint passes the engine harness (issue #1 acceptance), then both the endpoint and these files are removed.
