# Open WebUI Image Input Research

## Question

Why does Open WebUI currently return `No endpoints found that support image input` when images are uploaded in this deployment?

---

## TL;DR

Two root causes compound:

1. **The default model (`cheap` → `qwen/qwen3-coder`) is text-only** — OpenRouter's API confirms its `input_modalities` is `["text"]` with no image support. OpenRouter's routing layer rejects any chat completion containing `image_url` content for this model with HTTP 404: `No endpoints found that support image input`.

2. **`vision` is NOT in `DEFAULT_MODEL_METADATA`** — the env var only declares `web_search` and `builtin_tools` capabilities. This means Open WebUI's frontend hides the image upload button (gated by `capabilities.vision`), so the feature is doubly dead: UI-gated and model-incompatible.

The `deep` preset (Claude Opus 4.8) **does** support image input (`input_modalities: ["text", "image", "file"]`), but it is not the default and would need `vision: true` in its metadata to accept uploads.

**Update (same day):** the error was actually hit on `z-ai/glm-5.3`, which is likewise text-only per the Models API (`input_modalities: ["text"]`) — same root cause, different model. GLM vision-capable variants on OpenRouter: `glm-5.3-flash`, `glm-5.3-flashx`, `glm-5v-turbo`, `glm-4.6v`, `glm-4.5v` (`input_modalities` include `image`). Base `glm-5.3` / `glm-5.3-prime` are text-only.

---

## Findings

### 1. Error string origin: OpenRouter routing layer

**Source:** OpenRouter docs, [Image Inputs](https://openrouter.ai/docs/guides/overview/multimodal/image-understanding.md) and [Errors and Debugging](https://openrouter.ai/docs/api_reference/errors-and-debugging.md).

OpenRouter returns this exact error as an HTTP 404 when a chat completion request contains `image_url` content but the selected model has no provider endpoint that accepts image input:

> "If you get 'no endpoints found that support image input', you sent an image to a text-only model. Switch to a model whose `input_modalities` include `image`."

It is a pre-stream 404 — OpenRouter's routing layer evaluates the request content type against the model's declared modalities before forwarding to any upstream provider. If no provider endpoint for that model accepts images, the request is rejected immediately.

Confirmed by multiple third-party integrations hitting the same error (GitHub: musistudio/claude-code-router#419, anomalyco/opencode#10594, aaif-goose/goose#5396).

### 2. OpenRouter model modalities

**Source:** OpenRouter Models API (`GET /api/v1/model/<slug>`), fetched 2026-09-29.

| Model | `architecture.modality` | `architecture.input_modalities` | Vision? |
|---|---|---|---|
| `qwen/qwen3-coder` | `text->text` | `["text"]` | **No** |
| `anthropic/claude-opus-4.8` | `text+image+file->text` | `["text", "image", "file"]` | **Yes** |

Full API responses:
- `qwen/qwen3-coder`: `"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"]}` — text-only coding model, no image understanding.
- `anthropic/claude-opus-4.8`: `"architecture":{"modality":"text+image+file->text","input_modalities":["text","image","file"],"output_modalities":["text"]}` — accepts text, images, and files.

### 3. Open WebUI image upload gating

**Source:** Open WebUI docs ([Models](https://docs.openwebui.com/features/ai-knowledge/models), [Workspace Models](https://docs.openwebui.com/features/workspace/models/)) and GitHub issues.

Open WebUI gates image uploads at two levels:

**(a) Frontend UI gate — `capabilities.vision`**

The chat input checks `model.info?.meta?.capabilities?.vision` before showing the image upload button (GitHub: open-webui/open-webui#20129, Chat.svelte):

```javascript
if (hasImages && !(model.info?.meta?.capabilities?.vision ?? true)) {
    toast.error("Model {{modelName}} is not vision capable");
}
```

GitHub issue #18392 confirms: *"capabilities.vision: false prevents image uploads for that model"*.

**(b) Backend pass-through to provider**

When `vision: true` is set, Open WebUI converts uploaded images to base64 data URIs and includes them as `image_url` content parts in the chat completion request forwarded to the OpenAI-compatible API (OpenRouter in this case). Open WebUI does **not** auto-detect the upstream model's actual modalities — it trusts the `vision` capability flag and sends the image regardless. If the upstream model is text-only, OpenRouter returns the 404 error, which Open WebUI passes through to the user.

**(c) No fallback to document extraction for images**

Unlike text files (which go through RAG/document extraction), images with `vision: true` are sent as raw `image_url` content. There is no fallback OCR or description pipeline when the model lacks vision — the request simply fails upstream.

### 4. Current deployment configuration

**`DEFAULT_MODEL_METADATA`** (docker-compose.sweetpaintedlady.yml:129):
```
DEFAULT_MODEL_METADATA={"capabilities":{"web_search":true,"builtin_tools":true},"defaultFeatureIds":["web_search"]}
```

**`vision` is NOT declared.** This means:
- Neither the `cheap` nor `deep` preset has `vision: true` in their capabilities.
- The image upload button is hidden in the Open WebUI frontend for all models.
- If a user somehow uploads an image (e.g., via API, or after manually enabling vision in the Admin UI), the request reaches OpenRouter with the currently-selected model. If that model is `cheap` (qwen/qwen3-coder), OpenRouter returns 404.

**Preset models** (services/agenticui-config/models.json):
- `cheap` → base model `qwen/qwen3-coder` (text-only, no vision)
- `deep` → base model `anthropic/claude-opus-4.8` (vision-capable)

---

## What to change

### Required: enable `vision` in `DEFAULT_MODEL_METADATA`

**File:** `docker-compose.sweetpaintedlady.yml`, line 129

**Current:**
```
DEFAULT_MODEL_METADATA={"capabilities":{"web_search":true,"builtin_tools":true},"defaultFeatureIds":["web_search"]}
```

**Change to:**
```
DEFAULT_MODEL_METADATA={"capabilities":{"web_search":true,"builtin_tools":true,"vision":true},"defaultFeatureIds":["web_search"]}
```

This makes the image upload button visible for all models.

### Required: use only vision-capable models for image uploads

Since `qwen/qwen3-coder` is text-only (`input_modalities: ["text"]`), it will always return the OpenRouter 404 when sent images. Two options:

**Option A — Per-preset override (recommended):** In `services/agenticui-config/models.json`, add a `meta.capabilities` override to the `cheap` preset that disables vision, so the UI hides the upload button when that model is selected:

```json
{
  "id": "cheap",
  "meta": {
    "capabilities": { "vision": false },
    ...
  }
}
```

And add `vision: true` to the `deep` preset:

```json
{
  "id": "deep",
  "meta": {
    "capabilities": { "vision": true },
    ...
  }
}
```

Per-model overrides win over global defaults (Open WebUI docs: "Deep merge: {...global, ...per_model}").

**Option B — Replace the cheap model:** Swap `qwen/qwen3-coder` for a vision-capable Qwen model (e.g. `qwen/qwen3.6-27b` which has `input_modalities: ["text", "image", "video"]` per OpenRouter API), but this changes the coding model and cost profile.

### Summary of changes

| File | Change | Why |
|---|---|---|
| `docker-compose.sweetpaintedlady.yml` (line 129) | Add `"vision":true` to `DEFAULT_MODEL_METADATA.capabilities` | Enables image upload UI globally |
| `services/agenticui-config/models.json` (`deep` preset) | Add `"capabilities": {"vision": true}` to `meta` | Allows image uploads when Deep is selected |
| `services/agenticui-config/models.json` (`cheap` preset) | Add `"capabilities": {"vision": false}` to `meta` | Prevents image uploads when Cheap is selected (model is text-only) |

After changes, re-deploy with `./update.sh sweetpaintedlady` or `./restart.sh sweetpaintedlady`. Because `ENABLE_PERSISTENT_CONFIG=False`, env changes take effect on every container restart. The preset import (`seed-openwebui.sh`) runs during deploy and upserts the model metadata.
