#!/usr/bin/env bash
# deploy.sh — Deploy Deepgram self-hosted to Google Cloud Run with NVIDIA GPU
#
# Usage:
#   cp .env.example .env && $EDITOR .env
#   ./deploy.sh
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - envsubst installed (part of gettext; brew install gettext on macOS)
#   - Models uploaded to a GCS bucket (see README.md)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load .env if present ───────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

# ── Required variables ─────────────────────────────────────────────────────────
: "${GCP_PROJECT_ID:?'GCP_PROJECT_ID is required. Set it in .env or export it.'}"
: "${DEEPGRAM_MODELS_BUCKET:?'DEEPGRAM_MODELS_BUCKET is required. Set it in .env or export it.'}"
: "${DEEPGRAM_API_KEY:?'DEEPGRAM_API_KEY is required. Set it in .env or export it.'}"

# ── Defaults ───────────────────────────────────────────────────────────────────
GCP_REGION="${GCP_REGION:-us-central1}"
IMAGE_TAG="${IMAGE_TAG:-release-260305}"
# Registry hosting Deepgram container images. When QUAY_USERNAME is provided,
# deploy.sh creates an Artifact Registry remote repo that proxies quay.io with
# credentials and sets IMAGE_REGISTRY to the AR path automatically.
# You may also set IMAGE_REGISTRY directly to skip AR repo creation.
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
AR_REPO_NAME="${AR_REPO_NAME:-deepgram-quay}"
QUAY_PASSWORD_SECRET="${QUAY_PASSWORD_SECRET:-deepgram-quay-password}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-deepgram-cloud-run}"
DEEPGRAM_API_KEY_SECRET="${DEEPGRAM_API_KEY_SECRET:-deepgram-api-key}"
ENGINE_CONFIG_SECRET="deepgram-engine-config"
API_CONFIG_SECRET="deepgram-api-config"
ENGINE_SERVICE_NAME="${ENGINE_SERVICE_NAME:-deepgram-engine}"
API_SERVICE_NAME="${API_SERVICE_NAME:-deepgram-api}"
# VPC network for Cloud Run Direct VPC Egress.
# Set VPC_NETWORK to the name of an existing VPC to skip creation.
# Set VPC_SUBNETWORK to the name of an existing subnet in GCP_REGION to skip creation.
VPC_NETWORK="${VPC_NETWORK:-deepgram-vpc}"
VPC_SUBNETWORK="${VPC_SUBNETWORK:-deepgram-subnet}"
VPC_SUBNET_RANGE="${VPC_SUBNET_RANGE:-10.8.0.0/24}"
# Proxy-only subnet required by the internal HTTP load balancer.
VPC_PROXY_SUBNET="${VPC_PROXY_SUBNET:-deepgram-proxy-subnet}"
VPC_PROXY_SUBNET_RANGE="${VPC_PROXY_SUBNET_RANGE:-10.8.1.0/24}"
# Internal HTTP load balancer in front of the Engine.
ENGINE_LB_NAME="${ENGINE_LB_NAME:-deepgram-engine-lb}"
ENGINE_LB_IP_NAME="${ENGINE_LB_IP_NAME:-deepgram-engine-lb-ip}"

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Export for envsubst
export GCP_PROJECT_ID GCP_REGION IMAGE_TAG IMAGE_REGISTRY MODELS_BUCKET="${DEEPGRAM_MODELS_BUCKET}"
export SERVICE_ACCOUNT_EMAIL VPC_NETWORK VPC_SUBNETWORK

# ── Helpers ────────────────────────────────────────────────────────────────────
log()  { echo "  [deploy] $*"; }
step() { echo; echo "▶ $*"; }
die()  { echo "✖ ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed. $2"
}

secret_exists() {
  gcloud secrets describe "$1" \
    --project="${GCP_PROJECT_ID}" \
    --quiet 2>/dev/null
}

create_or_update_secret() {
  local secret_name="$1"
  local secret_value="$2"

  if secret_exists "${secret_name}"; then
    log "Updating existing secret: ${secret_name}"
    echo -n "${secret_value}" | gcloud secrets versions add "${secret_name}" \
      --project="${GCP_PROJECT_ID}" \
      --data-file=-
  else
    log "Creating new secret: ${secret_name}"
    echo -n "${secret_value}" | gcloud secrets create "${secret_name}" \
      --project="${GCP_PROJECT_ID}" \
      --replication-policy=automatic \
      --data-file=-
  fi
}

create_or_update_secret_from_file() {
  local secret_name="$1"
  local file_path="$2"

  if secret_exists "${secret_name}"; then
    log "Updating existing secret: ${secret_name}"
    gcloud secrets versions add "${secret_name}" \
      --project="${GCP_PROJECT_ID}" \
      --data-file="${file_path}"
  else
    log "Creating new secret: ${secret_name}"
    gcloud secrets create "${secret_name}" \
      --project="${GCP_PROJECT_ID}" \
      --replication-policy=automatic \
      --data-file="${file_path}"
  fi
}

# ── Preflight checks ───────────────────────────────────────────────────────────
step "Checking prerequisites"
require_cmd gcloud "Install from https://cloud.google.com/sdk/docs/install"
require_cmd envsubst "Install gettext: brew install gettext (macOS) or apt-get install gettext (Linux)"

gcloud config set project "${GCP_PROJECT_ID}" --quiet
log "Project: ${GCP_PROJECT_ID}"
log "Region:  ${GCP_REGION}"
log "Models bucket: gs://${DEEPGRAM_MODELS_BUCKET}"

# Verify the models bucket exists
if ! gsutil ls "gs://${DEEPGRAM_MODELS_BUCKET}" &>/dev/null; then
  die "GCS bucket 'gs://${DEEPGRAM_MODELS_BUCKET}' does not exist or is not accessible.
       Create it and upload your models before deploying. See README.md for guidance."
fi

# ── Quay.io credentials ────────────────────────────────────────────────────────
# Prompt for quay.io credentials if not already set in the environment.
# These are used to authenticate the Artifact Registry remote repo so it can
# pull private Deepgram images from quay.io on behalf of Cloud Run.
if [[ -z "${QUAY_USERNAME:-}" ]]; then
  read -r -p "  quay.io username: " QUAY_USERNAME
fi
if [[ -z "${QUAY_PASSWORD:-}" ]]; then
  read -r -s -p "  quay.io password / token: " QUAY_PASSWORD
  echo ""
fi
[[ -n "${QUAY_USERNAME}" ]] || die "quay.io username is required."
[[ -n "${QUAY_PASSWORD}" ]] || die "quay.io password is required."

# ── Enable required APIs ───────────────────────────────────────────────────────
step "Enabling required Google Cloud APIs"
gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  artifactregistry.googleapis.com \
  compute.googleapis.com \
  --project="${GCP_PROJECT_ID}" \
  --quiet
log "APIs enabled."

# ── Service account ────────────────────────────────────────────────────────────
step "Setting up service account: ${SERVICE_ACCOUNT_EMAIL}"
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${GCP_PROJECT_ID}" \
    --display-name="Deepgram Cloud Run service account" \
    --quiet
  log "Service account created."
else
  log "Service account already exists."
fi

# Wait for service account to propagate before applying IAM bindings.
# GCP can take a few seconds to make a newly created SA visible to IAM.
for i in $(seq 1 10); do
  if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" \
      --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
    break
  fi
  log "Waiting for service account to propagate (attempt ${i}/10)..."
  sleep 5
done

# Grant Secret Manager access (read secrets at runtime)
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet >/dev/null

# Grant GCS read access (models bucket via GCS FUSE)
gsutil iam ch \
  "serviceAccount:${SERVICE_ACCOUNT_EMAIL}:roles/storage.objectViewer" \
  "gs://${DEEPGRAM_MODELS_BUCKET}"

log "IAM permissions configured."

# ── VPC network ────────────────────────────────────────────────────────────────
step "Configuring VPC network: ${VPC_NETWORK}"

if gcloud compute networks describe "${VPC_NETWORK}" \
    --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Using existing VPC: ${VPC_NETWORK}"
else
  log "Creating VPC: ${VPC_NETWORK}"
  gcloud compute networks create "${VPC_NETWORK}" \
    --subnet-mode=custom \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

if gcloud compute networks subnets describe "${VPC_SUBNETWORK}" \
    --region="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Using existing subnet: ${VPC_SUBNETWORK} (${GCP_REGION})"
else
  log "Creating subnet: ${VPC_SUBNETWORK} (${GCP_REGION}, ${VPC_SUBNET_RANGE})"
  gcloud compute networks subnets create "${VPC_SUBNETWORK}" \
    --network="${VPC_NETWORK}" \
    --region="${GCP_REGION}" \
    --range="${VPC_SUBNET_RANGE}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

log "VPC ready: ${VPC_NETWORK} / ${VPC_SUBNETWORK}"

# ── Artifact Registry remote repo (quay.io proxy) ─────────────────────────────
step "Configuring Artifact Registry remote repo: ${AR_REPO_NAME}"

# Store the quay.io password in Secret Manager so AR can use it to authenticate.
create_or_update_secret "${QUAY_PASSWORD_SECRET}" "${QUAY_PASSWORD}"
log "quay.io password stored in secret: ${QUAY_PASSWORD_SECRET}"

QUAY_PASSWORD_SECRET_VERSION="projects/${GCP_PROJECT_ID}/secrets/${QUAY_PASSWORD_SECRET}/versions/latest"
AR_REPO_HOST="${GCP_REGION}-docker.pkg.dev"
AR_REPO_PATH="${AR_REPO_HOST}/${GCP_PROJECT_ID}/${AR_REPO_NAME}/deepgram"

# Grant Artifact Registry the ability to read the quay.io password secret.
PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')"
AR_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
gcloud secrets add-iam-policy-binding "${QUAY_PASSWORD_SECRET}" \
  --project="${GCP_PROJECT_ID}" \
  --member="serviceAccount:${AR_SERVICE_AGENT}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet >/dev/null

# Create or update the AR remote repo pointing at quay.io with credentials.
if gcloud artifacts repositories describe "${AR_REPO_NAME}" \
    --location="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Updating existing AR remote repo with quay.io credentials..."
  gcloud artifacts repositories update "${AR_REPO_NAME}" \
    --location="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --remote-username="${QUAY_USERNAME}" \
    --remote-password-secret-version="${QUAY_PASSWORD_SECRET_VERSION}" \
    --quiet
else
  log "Creating AR remote repo: ${AR_REPO_NAME}..."
  gcloud artifacts repositories create "${AR_REPO_NAME}" \
    --repository-format=docker \
    --location="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --description="Remote proxy for quay.io/deepgram" \
    --mode=remote-repository \
    --remote-repo-config-desc="quay.io" \
    --remote-docker-repo="https://quay.io" \
    --remote-username="${QUAY_USERNAME}" \
    --remote-password-secret-version="${QUAY_PASSWORD_SECRET_VERSION}" \
    --quiet
fi

# Grant Cloud Run's service agent read access to pull images from the AR repo.
CR_SERVICE_AGENT="service-${PROJECT_NUMBER}@serverless-robot-prod.iam.gserviceaccount.com"
gcloud artifacts repositories add-iam-policy-binding "${AR_REPO_NAME}" \
  --location="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --member="serviceAccount:${CR_SERVICE_AGENT}" \
  --role="roles/artifactregistry.reader" \
  --quiet >/dev/null

# Set IMAGE_REGISTRY to the AR remote repo path for use by envsubst in service YAMLs.
IMAGE_REGISTRY="${AR_REPO_PATH}"
export IMAGE_REGISTRY
log "Image registry: ${IMAGE_REGISTRY}"

# ── Secrets ────────────────────────────────────────────────────────────────────
step "Storing secrets in Secret Manager"

# Deepgram API key
create_or_update_secret "${DEEPGRAM_API_KEY_SECRET}" "${DEEPGRAM_API_KEY}"
log "API key stored in secret: ${DEEPGRAM_API_KEY_SECRET}"

# Engine config — upload the static engine.toml directly
create_or_update_secret_from_file \
  "${ENGINE_CONFIG_SECRET}" \
  "${SCRIPT_DIR}/config/engine.toml"
log "Engine config stored in secret: ${ENGINE_CONFIG_SECRET}"

# ── Deploy Engine service ──────────────────────────────────────────────────────
step "Deploying Engine service (GPU): ${ENGINE_SERVICE_NAME}"
log "Substituting template variables in engine.service.yaml..."
ENGINE_YAML="$(envsubst < "${SCRIPT_DIR}/services/engine.service.yaml")"

log "Applying Engine service definition..."
echo "${ENGINE_YAML}" | gcloud run services replace - \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --quiet

# Allow unauthenticated invocations within internal ingress.
# The Engine is only reachable by other Cloud Run services in the same project.
gcloud run services add-iam-policy-binding "${ENGINE_SERVICE_NAME}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --quiet

log "Engine service deployed."

# ── Internal HTTP load balancer for Engine ─────────────────────────────────────
step "Configuring internal HTTP load balancer: ${ENGINE_LB_NAME}"

ENGINE_LB_NEG="${ENGINE_LB_NAME}-neg"
ENGINE_LB_BACKEND="${ENGINE_LB_NAME}-backend"
ENGINE_LB_URL_MAP="${ENGINE_LB_NAME}-url-map"
ENGINE_LB_HTTP_PROXY="${ENGINE_LB_NAME}-http-proxy"

# Proxy-only subnet — required by INTERNAL_MANAGED HTTP load balancers.
if gcloud compute networks subnets describe "${VPC_PROXY_SUBNET}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Proxy-only subnet exists: ${VPC_PROXY_SUBNET}"
else
  log "Creating proxy-only subnet: ${VPC_PROXY_SUBNET} (${VPC_PROXY_SUBNET_RANGE})"
  gcloud compute networks subnets create "${VPC_PROXY_SUBNET}" \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --network="${VPC_NETWORK}" \
    --region="${GCP_REGION}" \
    --range="${VPC_PROXY_SUBNET_RANGE}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

# Reserve a static internal IP for the LB forwarding rule.
if gcloud compute addresses describe "${ENGINE_LB_IP_NAME}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "LB IP already reserved: ${ENGINE_LB_IP_NAME}"
else
  log "Reserving internal IP: ${ENGINE_LB_IP_NAME}"
  gcloud compute addresses create "${ENGINE_LB_IP_NAME}" \
    --region="${GCP_REGION}" \
    --subnet="${VPC_SUBNETWORK}" \
    --purpose=SHARED_LOADBALANCER_VIP \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

ENGINE_LB_IP="$(gcloud compute addresses describe "${ENGINE_LB_IP_NAME}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --format='value(address)')"
log "Engine LB IP: ${ENGINE_LB_IP}"

# Serverless NEG — points directly at the Engine Cloud Run service.
if gcloud compute network-endpoint-groups describe "${ENGINE_LB_NEG}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Serverless NEG exists: ${ENGINE_LB_NEG}"
else
  log "Creating serverless NEG: ${ENGINE_LB_NEG}"
  gcloud compute network-endpoint-groups create "${ENGINE_LB_NEG}" \
    --region="${GCP_REGION}" \
    --network-endpoint-type=serverless \
    --cloud-run-service="${ENGINE_SERVICE_NAME}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

# Backend service (HTTP, internal).
if gcloud compute backend-services describe "${ENGINE_LB_BACKEND}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Backend service exists: ${ENGINE_LB_BACKEND}"
else
  log "Creating backend service: ${ENGINE_LB_BACKEND}"
  gcloud compute backend-services create "${ENGINE_LB_BACKEND}" \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=HTTP \
    --region="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
  gcloud compute backend-services add-backend "${ENGINE_LB_BACKEND}" \
    --region="${GCP_REGION}" \
    --network-endpoint-group="${ENGINE_LB_NEG}" \
    --network-endpoint-group-region="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

# URL map.
if gcloud compute url-maps describe "${ENGINE_LB_URL_MAP}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "URL map exists: ${ENGINE_LB_URL_MAP}"
else
  log "Creating URL map: ${ENGINE_LB_URL_MAP}"
  gcloud compute url-maps create "${ENGINE_LB_URL_MAP}" \
    --default-service="${ENGINE_LB_BACKEND}" \
    --region="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

# HTTP target proxy — no TLS, plain HTTP only.
if gcloud compute target-http-proxies describe "${ENGINE_LB_HTTP_PROXY}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "HTTP proxy exists: ${ENGINE_LB_HTTP_PROXY}"
else
  log "Creating HTTP target proxy: ${ENGINE_LB_HTTP_PROXY}"
  gcloud compute target-http-proxies create "${ENGINE_LB_HTTP_PROXY}" \
    --url-map="${ENGINE_LB_URL_MAP}" \
    --region="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

# Forwarding rule — binds the reserved internal IP on port 80.
if gcloud compute forwarding-rules describe "${ENGINE_LB_NAME}" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Forwarding rule exists: ${ENGINE_LB_NAME}"
else
  log "Creating forwarding rule: ${ENGINE_LB_NAME} -> ${ENGINE_LB_IP}:80"
  gcloud compute forwarding-rules create "${ENGINE_LB_NAME}" \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --network="${VPC_NETWORK}" \
    --subnet="${VPC_SUBNETWORK}" \
    --address="${ENGINE_LB_IP_NAME}" \
    --region="${GCP_REGION}" \
    --target-http-proxy="${ENGINE_LB_HTTP_PROXY}" \
    --target-http-proxy-region="${GCP_REGION}" \
    --ports=80 \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

# Firewall rule — allow VPC subnet traffic to reach the LB on port 80.
if gcloud compute firewall-rules describe deepgram-allow-internal-http \
    --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
  log "Firewall rule exists: deepgram-allow-internal-http"
else
  log "Creating firewall rule: allow TCP:80 from ${VPC_SUBNET_RANGE}"
  gcloud compute firewall-rules create deepgram-allow-internal-http \
    --network="${VPC_NETWORK}" \
    --allow=tcp:80 \
    --source-ranges="${VPC_SUBNET_RANGE}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet
fi

log "Engine LB ready: http://${ENGINE_LB_IP}"

# The API talks to the Engine via the internal HTTP LB, not the Cloud Run URL.
ENGINE_SERVICE_URL="http://${ENGINE_LB_IP}"
log "Engine URL (for api.toml): ${ENGINE_SERVICE_URL}"

# ── Generate and store API config ──────────────────────────────────────────────
step "Generating API configuration"
API_TOML="$(sed "s|ENGINE_SERVICE_URL|${ENGINE_SERVICE_URL}|g" \
  "${SCRIPT_DIR}/config/api.toml.tmpl")"

# Write to a temp file so we can pass it to the secret command
TMPFILE="$(mktemp /tmp/api.toml.XXXXXX)"
trap 'rm -f "${TMPFILE}"' EXIT
echo "${API_TOML}" > "${TMPFILE}"

create_or_update_secret_from_file "${API_CONFIG_SECRET}" "${TMPFILE}"
log "API config stored in secret: ${API_CONFIG_SECRET} (Engine URL: ${ENGINE_SERVICE_URL})"

# ── Deploy API service ─────────────────────────────────────────────────────────
step "Deploying API service: ${API_SERVICE_NAME}"
log "Substituting template variables in api.service.yaml..."
API_YAML="$(envsubst < "${SCRIPT_DIR}/services/api.service.yaml")"

log "Applying API service definition..."
echo "${API_YAML}" | gcloud run services replace - \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --quiet

# Allow unauthenticated public access to the API service
gcloud run services add-iam-policy-binding "${API_SERVICE_NAME}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --quiet

log "API service deployed."

# Retrieve the API service URL
API_SERVICE_URL="$(gcloud run services describe "${API_SERVICE_NAME}" \
  --platform managed \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --format='value(status.url)')"

# ── Summary ────────────────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Deployment complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  API endpoint:    ${API_SERVICE_URL}/v1"
echo "  Engine endpoint: ${ENGINE_SERVICE_URL} (internal only)"
echo
echo "  Test with:"
echo "    curl -X POST \"${API_SERVICE_URL}/v1/listen\" \\"
echo "      -H \"Authorization: Token \${DEEPGRAM_API_KEY}\" \\"
echo "      -H \"Content-Type: audio/wav\" \\"
echo "      --data-binary @audio.wav"
echo
echo "  Logs:"
echo "    gcloud run services logs read ${API_SERVICE_NAME} --region=${GCP_REGION}"
echo "    gcloud run services logs read ${ENGINE_SERVICE_NAME} --region=${GCP_REGION}"
echo
