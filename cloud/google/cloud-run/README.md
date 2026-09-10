# Deepgram Self-Hosted on Google Cloud Run (NVIDIA GPU)

This directory contains everything needed to deploy Deepgram's self-hosted speech AI services on [Google Cloud Run](https://cloud.google.com/run) using NVIDIA L4 GPUs.

## Architecture

Each workload type requires its own dedicated API+Engine pair. The Deepgram API can only route to a single engine pool — there is no cross-workload request routing. Flux and Aura TTS **must not share** GPU instances with other models.

```
                          Internet
                             │
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ deepgram-api   │  │ deepgram-api   │  │ deepgram-api   │
│ (STT / nova)   │  │ -flux          │  │ -tts           │
│ public ingress │  │ public ingress │  │ public ingress │
│ listen_v2=false│  │ listen_v2=true │  │ speak_         │
│ speak_         │  │ speak_         │  │ streaming=true │
│ streaming=false│  │ streaming=false│  │ listen_v2=false│
└───────┬────────┘  └───────┬────────┘  └───────┬────────┘
        │ HTTPS             │ HTTPS             │ HTTPS
        │ (internal)        │ (internal)        │ (internal)
        ▼                   ▼                   ▼
┌───────────────┐  ┌────────────────┐  ┌────────────────────┐
│ deepgram-     │  │ deepgram-      │  │ deepgram-          │
│ engine        │  │ engine-flux    │  │ engine-tts         │
│ (STT / Nova)  │  │ (Flux only)    │  │ (Aura TTS only)    │
│ 1x L4 GPU     │  │ 1x L4 GPU      │  │ 2x L4 GPUs         │
│ 8 vCPU        │  │ 8 vCPU         │  │ 16 vCPU            │
│ 32 GiB RAM    │  │ 32 GiB RAM     │  │ 64 GiB RAM         │
│ Up to 5 nova  │  │ Dedicated;     │  │ Dedicated;         │
│ models/GPU    │  │ no other models│  │ CUDA_VISIBLE=0,1   │
└───────────────┘  └────────────────┘  └────────────────────┘
```

| API Service | Engine Service | Config Template | Workload |
|-------------|----------------|-----------------|----------|
| `deepgram-api` | `deepgram-engine` | `api.toml.tmpl` → `engine.toml` | nova-2/nova-3 STT |
| `deepgram-api-flux` | `deepgram-engine-flux` | `api-flux.toml.tmpl` → `engine-flux.toml` | Flux streaming STT |
| `deepgram-api-tts` | `deepgram-engine-tts` | `api-tts.toml.tmpl` → *(Deepgram-provided)* | Aura/Aura-2 TTS |

- **API services** — Each handles requests for one workload type only, routes to its paired Engine, and returns results. All are public HTTPS endpoints. Scale horizontally without GPU.
- **STT Engine** — Runs nova-2/nova-3 inference. Supports up to 5 concurrent model files per L4 GPU instance.
- **Flux Engine** — Runs Flux turn-based streaming STT. Must be fully isolated; no other models may share this instance. Requires `release-251015` or later.
- **TTS Engine** — Runs Aura/Aura-2 text-to-speech. Requires 2x L4 GPUs and dedicated hardware. Requires language-specific `IMPELLER_*` UUIDs from Deepgram.
- **Models** — Stored in GCS buckets and mounted read-only via [GCS FUSE](https://cloud.google.com/run/docs/storage/gcs-fuse). Use separate buckets per workload type to prevent accidental model mixing.
- **Secrets** — API key, TOML configs, and TTS model UUIDs stored in [Secret Manager](https://cloud.google.com/secret-manager) and mounted at container startup.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | Authenticated with `gcloud auth login` |
| [gettext](https://www.gnu.org/software/gettext/) (`envsubst`) | `brew install gettext` (macOS) / `apt-get install gettext` (Linux) |
| GCP project with billing enabled | GPU quota must be requested separately |
| NVIDIA L4 GPU quota | See [Request GPU quota](#1-request-gpu-quota) |
| Deepgram self-hosted API key | From [Deepgram console](https://developers.deepgram.com/docs/self-hosted-self-service-tutorial#create-a-self-hosted-api-key) |
| Model files in a GCS bucket | See [Upload models](#2-upload-models-to-gcs) |

## Deployment Guide

### 1. Request GPU quota

Cloud Run GPU instances require explicit quota approval. This step is done once per project.

1. Open the [GCP Quotas console](https://console.cloud.google.com/iam-admin/quotas).
2. Search for **`NVIDIA_L4_GPU`** under Cloud Run.
3. Request the total number of GPUs you need across all Engine services:
   - **STT Engine**: 1 GPU per replica × `maxScale` replicas
   - **Flux Engine**: 1 GPU per replica × `maxScale` replicas (if deploying Flux)
   - **TTS Engine**: **2 GPUs per replica** × `maxScale` replicas (if deploying Aura TTS)

   Example: 3 STT replicas + 2 Flux replicas + 1 TTS replica = 3 + 2 + 2 = **7 L4 GPUs**

Quota approval typically takes minutes to hours.

GPU availability by region:

| Region | L4 | A100 40GB | A100 80GB | H100 |
|--------|----|-----------|-----------| -----|
| `us-central1` | ✓ | ✓ | ✓ | ✓ |
| `us-east4` | ✓ | | | |
| `us-east1` | ✓ | | | |
| `europe-west1` | ✓ | | | |
| `asia-northeast1` | ✓ | | | |

L4 is the recommended starting point for most inference workloads. To use a different GPU, change `run.googleapis.com/gpu-type` in `services/engine.service.yaml` and update `maxReplicas` to stay within your quota.

### 2. Upload models to GCS

The Engine container reads models from a GCS bucket mounted at `/models` via GCS FUSE. The bucket must be populated before deployment.

```bash
# Create the bucket (if it does not already exist)
gsutil mb -p YOUR_PROJECT_ID -l us-central1 gs://YOUR_MODELS_BUCKET

# Upload your model files
# Model files are typically provided by Deepgram as .dg archives or directories.
gsutil -m cp -r /local/path/to/models/* gs://YOUR_MODELS_BUCKET/
```

The `engine.toml` config sets `search_paths = ["/models"]`, so place model files at the top level of the bucket or in subdirectories — the Engine will scan recursively.

Example bucket layout for the STT (nova) engine:
```
gs://YOUR_MODELS_BUCKET/
├── nova-2-general/
│   └── model.dg
└── nova-3-general/
    └── model.dg
```

Use **separate GCS buckets** per workload type to prevent models from being accidentally loaded on the wrong engine:

| Workload | Recommended bucket name | Contents |
|----------|------------------------|----------|
| STT (nova) | `your-project-stt-models` | nova-2, nova-3 model files |
| Flux | `your-project-flux-models` | Flux model file only |
| TTS (Aura) | `your-project-tts-models` | Aura/Aura-2 model files |

An L4 GPU can host **up to 5 nova-2/nova-3 model files** concurrently. Set `max_concurrently_loaded_models = 5` in `engine.toml` to enforce this limit.

### 3. Configure environment

```bash
cd cloud-run/
cp .env.example .env
$EDITOR .env
```

The minimum required values in `.env`:

```bash
GCP_PROJECT_ID=your-project-id
DEEPGRAM_MODELS_BUCKET=your-models-bucket
DEEPGRAM_API_KEY=your_deepgram_api_key
```

Optional values (defaults are shown in `.env.example`):

| Variable | Default | Description |
|----------|---------|-------------|
| `GCP_REGION` | `us-central1` | Deployment region (must support L4 GPU) |
| `IMAGE_TAG` | `release-260305` | Deepgram container image tag |
| `SERVICE_ACCOUNT_NAME` | `deepgram-cloud-run` | GCP service account name |
| `ENGINE_SERVICE_NAME` | `deepgram-engine` | Cloud Run Engine service name |
| `API_SERVICE_NAME` | `deepgram-api` | Cloud Run API service name |

### 4. (Optional) Customize configuration

Edit `config/engine.toml` and `config/api.toml.tmpl` before deploying to adjust model settings, concurrency limits, or feature flags.

Key Engine settings to review:

```toml
# Limit concurrent requests per GPU instance.
# For STT streaming on an L4, start with 8–16 and tune based on load.
# max_active_requests = 16

# Pre-load models at startup so the first request has no cold-start latency.
# blocking = true means Cloud Run will not send traffic until models are loaded.
[preload_models]
blocking = true
```

Key API settings to review:

```toml
# Limit concurrent requests per API replica to avoid memory pressure.
[concurrency_limit]
# active_requests = 100
```

`config/api.toml.tmpl` contains the placeholder `ENGINE_SERVICE_URL` which `deploy.sh` replaces automatically with the Engine's Cloud Run URL.

### 5. Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

The script performs these steps automatically:

1. Enables required GCP APIs (`run`, `secretmanager`, `storage`, `iam`)
2. Creates a service account with the minimum required permissions
3. Stores your Deepgram API key and TOML configs in Secret Manager
4. Deploys the **Engine** Cloud Run service (GPU, internal ingress)
5. Retrieves the Engine's HTTPS URL and substitutes it into `api.toml.tmpl`
6. Uploads the generated `api.toml` to Secret Manager
7. Deploys the **API** Cloud Run service (public ingress)
8. Prints the public API endpoint and sample curl command

Deployment takes approximately **5–10 minutes** on the first run (model preloading and GCS FUSE initialization dominate startup time). Subsequent deployments are faster.

### 6. Verify the deployment

```bash
# Substitute the URL printed by deploy.sh
API_URL=https://deepgram-api-XXXX-uc.a.run.app

# Check API status
curl "${API_URL}/v1/status"

# Transcribe a WAV file
curl -X POST "${API_URL}/v1/listen?model=nova-2" \
  -H "Authorization: Token ${DEEPGRAM_API_KEY}" \
  -H "Content-Type: audio/wav" \
  --data-binary @audio.wav
```

## Updating configuration

To update `engine.toml` or `api.toml` without redeploying the full stack:

```bash
# Update engine config
gcloud secrets versions add deepgram-engine-config \
  --data-file=config/engine.toml

# Force a new Engine revision to pick up the new config
gcloud run services update deepgram-engine \
  --region=us-central1 \
  --update-env-vars=CONFIG_RELOAD="$(date +%s)"
```

Or re-run `./deploy.sh` — it is idempotent and will update all secrets and redeploy both services.

## Deploying Flux (dedicated STT)

Flux requires its own dedicated Cloud Run service and must not share GPU instances with other models.

**Requirements (from Deepgram docs):**
- Container image `release-251015` or later (current default satisfies this)
- 1x NVIDIA L4 GPU per instance, fully isolated — no nova, TTS, or supplementary models
- `flux.max_streams` explicitly set in `engine-flux.toml` (contact Deepgram for L4 value)
- `max_active_requests` does **not** apply to Flux; use `flux.max_streams` instead

**Steps:**

1. Create a separate GCS bucket for the Flux model file only.

2. Store the Flux engine config in Secret Manager:
   ```bash
   gcloud secrets create deepgram-engine-flux-config \
     --data-file=config/engine-flux.toml \
     --project=${GCP_PROJECT_ID}
   ```

3. Deploy the Flux Engine service:
   ```bash
   envsubst < services/engine-flux.service.yaml | \
     gcloud run services replace - --region=${GCP_REGION} --project=${GCP_PROJECT_ID}
   ```

4. Retrieve the Flux Engine URL and generate the Flux API config:
   ```bash
   FLUX_ENGINE_URL=$(gcloud run services describe deepgram-engine-flux \
     --platform managed --region=${GCP_REGION} --project=${GCP_PROJECT_ID} \
     --format='value(status.url)')

   sed "s|FLUX_ENGINE_SERVICE_URL|${FLUX_ENGINE_URL}|g" \
     config/api-flux.toml.tmpl > /tmp/api-flux.toml

   gcloud secrets create deepgram-api-flux-config \
     --data-file=/tmp/api-flux.toml \
     --project=${GCP_PROJECT_ID}
   ```

5. Deploy the Flux API service:
   ```bash
   envsubst < services/api-flux.service.yaml | \
     gcloud run services replace - --region=${GCP_REGION} --project=${GCP_PROJECT_ID}
   ```

**Monitor Flux capacity** via the Engine metrics endpoint:
```
flux_used_streams     — active streams
flux_max_streams      — configured maximum
flux_fraction_streams — scale out when this approaches 0.8
```

---

## Deploying Aura TTS (dedicated TTS)

Aura TTS requires its own dedicated Cloud Run service with 2x NVIDIA L4 GPUs per instance.

**Requirements (from Deepgram docs):**
- 2x NVIDIA L4 GPUs (32 GB GPU RAM total) per instance
- 8+ CPU cores and 64 GiB RAM per instance (reflected as 16 vCPU / 64 GiB in the service YAML)
- `CUDA_VISIBLE_DEVICES=0,1` to expose both GPUs to the TTS engine
- Language-specific `IMPELLER_AURA2_T2C_UUID` and `IMPELLER_AURA2_C2A_UUID` env vars (provided by Deepgram)
- Dedicated hardware — do not mix with STT or Flux workloads

**Steps:**

1. Obtain your Aura-2 model UUIDs from your Deepgram Account Representative.

2. Store the UUIDs in Secret Manager:
   ```bash
   echo -n "YOUR_T2C_UUID" | gcloud secrets create deepgram-tts-t2c-uuid \
     --data-file=- --project=${GCP_PROJECT_ID}

   echo -n "YOUR_C2A_UUID" | gcloud secrets create deepgram-tts-c2a-uuid \
     --data-file=- --project=${GCP_PROJECT_ID}
   ```

3. Store the TTS engine config (provided by Deepgram) in Secret Manager:
   ```bash
   gcloud secrets create deepgram-engine-tts-config \
     --data-file=path/to/engine-tts.toml \
     --project=${GCP_PROJECT_ID}
   ```

4. Grant the service account access to the new secrets:
   ```bash
   for SECRET in deepgram-tts-t2c-uuid deepgram-tts-c2a-uuid deepgram-engine-tts-config; do
     gcloud secrets add-iam-policy-binding ${SECRET} \
       --project=${GCP_PROJECT_ID} \
       --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
       --role="roles/secretmanager.secretAccessor"
   done
   ```

5. Request **2x** NVIDIA_L4_GPU quota per TTS replica in the GCP console.

6. Deploy the TTS Engine service:
   ```bash
   envsubst < services/engine-tts.service.yaml | \
     gcloud run services replace - --region=${GCP_REGION} --project=${GCP_PROJECT_ID}
   ```

7. Retrieve the TTS Engine URL and generate the TTS API config:
   ```bash
   TTS_ENGINE_URL=$(gcloud run services describe deepgram-engine-tts \
     --platform managed --region=${GCP_REGION} --project=${GCP_PROJECT_ID} \
     --format='value(status.url)')

   sed "s|TTS_ENGINE_SERVICE_URL|${TTS_ENGINE_URL}|g" \
     config/api-tts.toml.tmpl > /tmp/api-tts.toml

   gcloud secrets create deepgram-api-tts-config \
     --data-file=/tmp/api-tts.toml \
     --project=${GCP_PROJECT_ID}
   ```

8. Deploy the TTS API service:
   ```bash
   envsubst < services/api-tts.service.yaml | \
     gcloud run services replace - --region=${GCP_REGION} --project=${GCP_PROJECT_ID}
   ```

For full TTS deployment details, see the [Deepgram Deploy TTS Services guide](https://developers.deepgram.com/docs/deploy-tts-services).

---

## Scaling

### Engine replicas

Edit the autoscaling annotations in `services/engine.service.yaml`:

```yaml
autoscaling.knative.dev/minScale: "1"   # Warm GPU instances (0 = scale to zero, cold starts ~2–5 min)
autoscaling.knative.dev/maxScale: "3"   # Must be within your L4 GPU quota
```

Cloud Run scales the Engine on incoming request concurrency. Tune `max_active_requests` in `engine.toml` to control how many requests each Engine pod accepts before Cloud Run routes to a new replica.

### API replicas

The API service scales on request concurrency automatically. It does not require GPU and scales quickly. Adjust `maxScale` in `services/api.service.yaml` if you need more API throughput.

### Switching GPU types

To use A100 or H100 instead of L4:

1. Verify GPU availability in your region (see the table above).
2. Change the annotation in `services/engine.service.yaml`:
   ```yaml
   run.googleapis.com/gpu-type: nvidia-a100-80gb
   ```
3. Request the appropriate quota and adjust `cpu`/`memory` limits accordingly.
4. Re-run `./deploy.sh`.

## Cost considerations

- **GPU instances** are the dominant cost. An NVIDIA L4 on Cloud Run is billed per second of request processing (when `minScale: "0"`) or per-instance-hour (when `minScale: "1"`).
- Setting `minScale: "0"` on the Engine eliminates idle cost but introduces a **cold start of 2–5 minutes** (GPU allocation + model loading).
- Setting `minScale: "1"` keeps one warm GPU instance running at all times for immediate response, at the cost of continuous GPU billing.
- The API service is cheap — a few vCPUs with no GPU.

Estimate your costs using the [Cloud Run pricing calculator](https://cloud.google.com/products/calculator).

## Limitations

| Limitation | Detail |
|------------|--------|
| **Request size** | Cloud Run's HTTP load balancer accepts up to 32 MB per request body. For larger audio files, use the `url` query parameter to fetch audio from a remote URL, or use the `callback` parameter for async transcription. |
| **Streaming WebSockets** | Cloud Run supports WebSocket connections (HTTP/2). Streaming STT over WebSocket works, but individual connections are limited to the service `timeoutSeconds` (default: 3600s). |
| **Metrics port** | The Engine metrics server runs on port 9991, which is not exposed by Cloud Run's load balancer. To scrape metrics, deploy a Cloud Run sidecar container or use Cloud Run's built-in metrics in Cloud Monitoring. |
| **Model cold start** | If `preload_models.blocking = true`, Cloud Run will not route requests to a new Engine instance until all models are loaded (~1–3 min). This is safer than allowing requests during loading. |
| **Voice agent** | Voice agent (`agent.enabled`) requires persistent bidirectional state. Cloud Run can handle WebSocket-based agent sessions but has not been validated for production voice agent workloads. |

## Logs and monitoring

```bash
# Tail API logs
gcloud run services logs tail deepgram-api --region=us-central1

# Tail Engine logs (GPU instance)
gcloud run services logs tail deepgram-engine --region=us-central1

# View all logs in Cloud Logging
gcloud logging read \
  'resource.type="cloud_run_revision" resource.labels.service_name="deepgram-engine"' \
  --limit=100 --format=json
```

Cloud Run automatically exports metrics (request count, latency, instance count) to [Cloud Monitoring](https://console.cloud.google.com/monitoring). GPU utilization metrics require [DCGM](https://developer.nvidia.com/dcgm) which is not currently available in Cloud Run.

## Teardown

```bash
# Remove Cloud Run services and secrets (keeps GCS bucket and service account)
./teardown.sh

# Remove everything including the service account
./teardown.sh --all
```

The GCS models bucket is never deleted automatically. Delete it manually when no longer needed:

```bash
gsutil -m rm -r gs://YOUR_MODELS_BUCKET
```

## Directory structure

```
cloud-run/
├── README.md                         # This file
├── deploy.sh                         # Deployment script (STT / nova baseline)
├── teardown.sh                       # Cleanup script
├── .env.example                      # Environment variable template
├── config/
│   ├── engine.toml                   # STT Engine config (nova-2 / nova-3)
│   ├── engine-flux.toml              # Flux Engine config (dedicated)
│   ├── api.toml.tmpl                 # STT API config template (ENGINE_SERVICE_URL)
│   ├── api-flux.toml.tmpl            # Flux API config template (FLUX_ENGINE_SERVICE_URL)
│   └── api-tts.toml.tmpl             # TTS API config template (TTS_ENGINE_SERVICE_URL)
└── services/
    ├── api.service.yaml              # Cloud Run API — STT (nova)
    ├── api-flux.service.yaml         # Cloud Run API — Flux (dedicated)
    ├── api-tts.service.yaml          # Cloud Run API — Aura TTS (dedicated)
    ├── engine.service.yaml           # Cloud Run Engine — STT (1x GPU, nova)
    ├── engine-flux.service.yaml      # Cloud Run Engine — Flux (1x GPU, dedicated)
    └── engine-tts.service.yaml       # Cloud Run Engine — TTS (2x GPU, Aura, dedicated)
```

## Getting help

See the [Getting Help](../README.md#getting-help) section in the root of this repository for a list of resources to help you troubleshoot and resolve issues.
