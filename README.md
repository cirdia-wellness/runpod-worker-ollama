# Cirdia LLM Endpoint — vLLM serving for the insight engine

*Who reads this: whoever creates, changes, or retires the LLM serving endpoints the PIE worker calls. The engine-side contract lives in `ephemeral-instance` (issue #39); this repo owns what the endpoint **is**.*

## What this is

The insight engine's LLM endpoint runs **vLLM** (RunPod's official serverless worker image) serving the **original Apache-2.0 weights** of `mistralai/Ministral-3-8B-Instruct-2512`, with **server-enforced structured output** (`response_format: json_schema`).

Why vLLM and original weights: the previous Ollama-based endpoint served a quantized copy that ignored editorial instructions — no correlation findings, clinical/advice leakage, broken formatting (issue #1). A control run of identical prompts against strict-enforcement serving of original weights produced the designed report. Self-hosting is a PIE invariant — no third-party inference APIs, ever.

**Licensing:** Ministral 3 (2512) is Apache 2.0 — commercially usable. Do **not** substitute `Ministral-8B-Instruct-2410`; it is Mistral Research License (non-commercial).

## Endpoint definition

The source of truth for every setting is [`vllm/endpoint.dev.json`](vllm/endpoint.dev.json). Prod gets a twin (`vllm-ministral-prod`) at the prod cutover — same file pattern, separate endpoint.

## Creating the dev endpoint (RunPod console)

1. **Serverless → New Endpoint → Docker image** → `runpod/worker-v1-vllm:stable-cuda12.1.0`
2. Name: `vllm-ministral-dev` · GPU: **24GB tier** · Max workers 2, active 0
3. Environment variables — exactly the `env` block from `vllm/endpoint.dev.json` (the `HF_TOKEN` is a Hugging Face token created after accepting the model's terms on its HF page — needed to download the weights)
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
