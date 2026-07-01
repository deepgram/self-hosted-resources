# deepgram-aiworks

Helm chart for VoiceWorks (AIWorks) self-hosted. Deploys the AIWorks
backend alongside or independent of the Deepgram speech distribution
(`deepgram-self-hosted`). Backend-only for v1; no frontend.

## Prerequisites

- Kubernetes 1.28+
- A reachable `license-proxy` endpoint. Two ways to get one:
  - Already running `deepgram-self-hosted` (most common). Point
    `license.serverUrl` at `http://license-proxy.<namespace>.svc.cluster.local:8080`.
  - Standalone license-proxy deployment (out of scope for this chart;
    see Deepgram self-hosted docs).
- A self-hosted Deepgram speech endpoint (STT). Point
  `deepgram.streamingListenUrl` and `deepgram.batchListenUrl` at it.
- Container registry access to `quay.io/deepgram/voiceworks-self-hosted`.
  Add an `imagePullSecret` to `imagePullSecrets[]` if needed.

## Quick start

```sh
helm repo add deepgram https://deepgram.github.io/self-hosted-resources
helm install aiworks deepgram/deepgram-aiworks \
  --set license.apiKey=<your-deepgram-api-key-uuid> \
  --set selfHosted.apiKey=<your-40-plus-char-shared-secret> \
  --set selfHosted.bootstrapSubject=<fresh-uuid-v4>
```

Connect to the AIWorks WebSocket execute endpoint:

```
ws://<service-or-ingress>/api/repos/<any-uuid>/flows/<flow-slug>/execute
Authorization: Token <selfHosted.apiKey>
```

In files mode the `<any-uuid>` is just routing decoration — flows are
looked up by slug.

## Storage modes

| Mode | Use when | Persistence |
|---|---|---|
| `files` (default) | You design flows on cloud (`aiworks.deepgram.com`), export to JSON, drop them in the `flows/` PVC | PVC at `storage.files.flowsDir` |
| `postgres` | You want the cloud-shape DB-backed flow store | Pass `storage.postgres.dsn` |

See [the self-hosted concepts](https://github.com/deepgram/voiceworks/blob/master/documentation/concepts/self-hosted.md)
for the two-knobs model and full deployment matrix.

## Examples

### Files mode + open mode (most common)

```sh
helm install aiworks deepgram/deepgram-aiworks \
  -f - <<EOF
license:
  apiKey: "12345678-1234-5678-abcd-beefdeadbeef"
  serverUrl:
    - "http://license-proxy.deepgram.svc.cluster.local:8080"
selfHosted:
  apiKey: "a-fresh-shared-secret-of-at-least-forty-chars"
  bootstrapSubject: "$(uuidgen)"
storage:
  mode: files
  files:
    persistence:
      enabled: true
      size: 5Gi
deepgram:
  streamingListenUrl: "ws://api.deepgram.svc.cluster.local:8080/v1/listen"
  batchListenUrl: "http://api.deepgram.svc.cluster.local:8080/v1/listen"
EOF
```

### Behind an ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: aiworks.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts: [aiworks.example.com]
      secretName: aiworks-tls
```

### In-process TLS (no ingress)

```yaml
server:
  tls:
    enabled: true
    # Inline (chart creates a kubernetes.io/tls Secret):
    cert: |
      -----BEGIN CERTIFICATE-----
      ...
    key: |
      -----BEGIN PRIVATE KEY-----
      ...
    # Or reference an existing Secret:
    # existingSecret: aiworks-tls
```

SIGHUP triggers cert hot-reload — when the cert file in the mounted
Secret changes (e.g., cert-manager rotation), send a SIGHUP to the
pod:
```sh
kubectl exec -it aiworks-<id> -- kill -HUP 1
```
Or rely on the pod's `terminationGracePeriodSeconds` to drain a
rolling update.

### Postgres mode

```yaml
storage:
  mode: postgres
  postgres:
    dsn: "postgres://user:pass@db.example.com:5432/voiceworks"
```

## Upgrading

```sh
helm upgrade aiworks deepgram/deepgram-aiworks \
  --reuse-values \
  --set image.tag=<new-version>
```

Default `updateStrategy.rollingUpdate.maxUnavailable=0` keeps at least
one pod serving during the roll. Long-lived WebSocket sessions are
drained over `terminationGracePeriodSeconds`.

## Uninstalling

```sh
helm uninstall aiworks
```

Persistent volumes are retained per the cluster's reclaim policy.
Manually delete the PVC if you want to free the storage.

## Values reference

The most commonly-tuned values:

| Key | Type | Default | Description |
|---|---|---|---|
| `image.repository` | string | `quay.io/deepgram/voiceworks-self-hosted` | Container image |
| `image.tag` | string | `""` (defaults to `.Chart.appVersion`) | Image tag |
| `replicaCount` | int | `1` | Static replicas when HPA off |
| `license.apiKey` | string | `""` (required) | License UUID; stored as `DEEPGRAM_API_KEY` in Secret |
| `license.apiKeyExistingSecret` | string | `""` | Reference existing Secret instead of creating one |
| `license.serverUrl` | list | `["http://license-proxy.deepgram.svc.cluster.local:8080", "https://license.deepgram.com"]` | License server URLs (priority order) |
| `license.proxyStatusUrl` | string | `""` | Optional hermes /v1/status gate at startup |
| `storage.mode` | string | `files` | `"files"` or `"postgres"` |
| `storage.files.flowsDir` | string | `/flows` | Container mount path for flow JSONs |
| `storage.files.persistence.enabled` | bool | `true` | Provision a PVC for flows |
| `storage.files.persistence.size` | string | `1Gi` | PVC size |
| `storage.files.persistence.storageClassName` | string | `""` | StorageClass (empty = default) |
| `storage.files.persistence.existingClaim` | string | `""` | Reuse an existing PVC |
| `storage.postgres.dsn` | string | `""` | Postgres DSN (required when `mode=postgres`) |
| `selfHosted.enabled` | bool | `true` | Open-mode auth bypass |
| `selfHosted.apiKey` | string | `""` (required when enabled) | Shared-secret token; stored as `VW_API_KEY` in Secret. **voiceworks resolves `${VW_API_KEY}` from the pod env at startup** — the literal string `"${VW_API_KEY}"` is what gets written to `config.toml`. |
| `selfHosted.bootstrapSubject` | string | `""` (required when enabled) | Fresh UUID; **never reuse a UUID with existing data** |
| `deepgram.streamingListenUrl` | string | `ws://api.deepgram.svc.cluster.local:8080/v1/listen` | Deepgram streaming STT endpoint |
| `deepgram.batchListenUrl` | string | `http://api.deepgram.svc.cluster.local:8080/v1/listen` | Deepgram batch STT endpoint |
| `server.host` | string | `0.0.0.0` | Bind address |
| `server.port` | int | `8080` | Bind port |
| `server.tls.enabled` | bool | `false` | Terminate TLS in voiceworks itself |
| `server.tls.cert` | string | `""` | PEM cert chain (inline; required when `tls.enabled` and no `existingSecret`) |
| `server.tls.key` | string | `""` | PEM private key (inline) |
| `server.tls.existingSecret` | string | `""` | Reference an existing `kubernetes.io/tls` Secret |
| `server.tls.clientCaBundle` | string | `""` | Optional CA bundle for mTLS |
| `service.type` | string | `ClusterIP` | Service type |
| `service.port` | int | `8080` | Service port |
| `ingress.enabled` | bool | `false` | Provision an Ingress |
| `scaling.auto.enabled` | bool | `false` | Enable HPA |
| `scaling.auto.minReplicas` | int | `1` | HPA min |
| `scaling.auto.maxReplicas` | int | `5` | HPA max |
| `scaling.auto.targetCPUUtilizationPercentage` | int | `70` | HPA CPU target |
| `networkPolicy.enabled` | bool | `false` | Provision a NetworkPolicy |
| `serviceMonitor.enabled` | bool | `false` | Provision a kube-prometheus-stack ServiceMonitor |
| `resources.requests` | object | `{cpu: 100m, memory: 256Mi}` | Container resource requests |
| `resources.limits` | object | `{cpu: 1000m, memory: 1Gi}` | Container resource limits |
| `terminationGracePeriodSeconds` | int | `60` | Pod termination grace |
| `updateStrategy.rollingUpdate.maxUnavailable` | int/string | `0` | Rolling update max unavailable |
| `updateStrategy.rollingUpdate.maxSurge` | int/string | `1` | Rolling update max surge |
| `probes.readiness.*` / `probes.liveness.*` / `probes.startup.*` | various | see `values.yaml` | Probe tuning |
| `secrets.existingSecret` | string | `""` | Reference existing Secret for license + open-mode creds (bypasses chart Secret creation) |
| `imagePullSecrets` | list | `[]` | Pod `imagePullSecrets` |
| `nodeSelector` / `tolerations` / `affinity` | various | `{}` / `[]` / `{}` | Pod scheduling |
| `podLabels` / `podAnnotations` | various | `{}` | Pod metadata |
| `podSecurityContext` / `securityContext` | various | non-root UID 10001, read-only root, all caps dropped | Pod / container security |

See `values.yaml` for the full schema with inline comments.
