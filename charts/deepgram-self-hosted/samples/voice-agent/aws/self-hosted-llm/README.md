# Voice Agent on AWS with a self-hosted LLM

This sample deploys the Deepgram self-hosted **Voice Agent** on AWS EKS and
routes it to a **self-hosted LLM** — NVIDIA NIM serving a Nemotron model —
running in the same cluster. No third-party LLM API key is required; the agent
reaches the LLM entirely over the in-cluster network.

## How it works

The Deepgram Helm chart does **not** deploy the LLM. NIM is installed as a
separate Helm release into a dedicated node group. The Voice Agent's
"Bring Your Own LLM" support is what connects the two: when the client app
sets `think.endpoint` in its per-session Settings payload, the agent POSTs
chat-completion requests directly to that URL (NIM exposes an OpenAI-compatible
API). Two chart values let the in-cluster NIM URL pass server-side validation:

- `agent.allowNonpublicEndpoints: true` — allows cluster-local DNS names.
- `agent.allowInsecureEndpoints: true` — allows `http://`, since the in-cluster
  NIM service is plain HTTP by default. Drop this if you terminate TLS in front
  of NIM.

## Files

| File | Purpose |
| --- | --- |
| `cluster-config.yaml` | `eksctl` cluster definition. Adds an `llm-node-group` to host NIM alongside the standard api / engine / license-proxy groups. |
| `values.yaml` | Values for the `deepgram-self-hosted` Helm release (Voice Agent + Aura-2 TTS, with BYO-LLM enabled). |
| `nim-values.yaml` | Values for the **separate** NVIDIA `nim-llm` Helm release. |

## Prerequisites

- `eksctl`, `kubectl`, and `helm` installed and configured.
- A Deepgram self-hosted API key and image-pull credentials for `quay.io`.
- An NGC API key (`$NGC_API_KEY`) with access to the NVIDIA NIM catalog.

## Deployment

> Replace `dg-self-hosted` below if you install into a different namespace, and
> review the placeholder values flagged with `# Change ...` / `# Replace ...`
> comments in each YAML file (cluster name, region, EFS filesystem ID, etc.).

### 1. Create the cluster

```bash
eksctl create cluster -f cluster-config.yaml
```

### 2. Create namespace and Deepgram secrets

```bash
kubectl create namespace dg-self-hosted

kubectl create secret docker-registry dg-regcred \
  --docker-server=quay.io \
  --docker-username='QUAY_DG_USER' \
  --docker-password='QUAY_DG_PASSWORD' \
  -n dg-self-hosted

kubectl create secret generic dg-self-hosted-api-key \
  --from-literal=DEEPGRAM_API_KEY='<your-api-key>' \
  -n dg-self-hosted
```

### 3. Install NVIDIA NIM (the LLM)

NGC does **not** publish a standard Helm chart-repo index, so
`helm repo add` will fail. Fetch a versioned `.tgz` instead. `1.3.0` is the
version NVIDIA references in their AWS EKS NIM deployment guide — check the
`nim-llm` page on NGC for newer versions.

```bash
# NGC image-pull + API-key secrets (one-time per namespace)
kubectl create secret docker-registry ngc-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password="$NGC_API_KEY" \
  -n dg-self-hosted
kubectl create secret generic ngc-api \
  --from-literal=NGC_API_KEY="$NGC_API_KEY" \
  -n dg-self-hosted

# Fetch the nim-llm chart .tgz
helm fetch https://helm.ngc.nvidia.com/nim/charts/nim-llm-1.3.0.tgz \
  --username='$oauthtoken' --password="$NGC_API_KEY"

# Install NIM from the local .tgz
helm install nemotron-nim nim-llm-1.3.0.tgz \
  -n dg-self-hosted \
  -f nim-values.yaml
```

Once running, NIM is reachable in-cluster at:

```
http://nemotron-nim.dg-self-hosted.svc.cluster.local:8000/v1
```

### 4. Install the Deepgram chart

```bash
helm install deepgram deepgram/deepgram-self-hosted \
  -n dg-self-hosted \
  -f values.yaml
```

### 5. Point the Voice Agent at NIM

The agent learns the LLM endpoint from the client app's per-session Settings
payload, not from the chart. Send a `think` block like:

```yaml
think:
  provider:
    type: open_ai          # NIM exposes an OpenAI-compatible API
    model: <model name served by NIM>
  endpoint:
    url: http://nemotron-nim.dg-self-hosted.svc.cluster.local:8000/v1/chat/completions
    headers:
      Authorization: "Bearer <token if NIM auth is enabled, else any value>"
```

## Choosing a Nemotron variant

`nim-values.yaml` defaults to **Llama-3.1-Nemotron-Nano-8B** on a single L40S
(`g6e.xlarge`). To run the larger **Super-49B** variant, swap the image
repository and bump the GPU count/instance type — see the inline comments in
`nim-values.yaml` and `cluster-config.yaml` for the specific values.

## Notes

- Autoscaling is not yet supported for the Voice Agent; replica counts are fixed.
- Do **not** add a custom provider key (e.g. `nvidia`) under
  `agent.llmProviders` in `values.yaml` — only the built-in provider keys are
  accepted. The agent reaches NIM via the per-session `think.endpoint` instead.
- Do not expose the NIM service to the public internet without authentication.

See the chart [README](../../../../README.md) and
[values.yaml](../../../../values.yaml) for documentation on all available options.
