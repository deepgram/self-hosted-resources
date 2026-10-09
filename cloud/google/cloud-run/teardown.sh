#!/usr/bin/env bash
# teardown.sh — Remove Deepgram Cloud Run services and associated resources
#
# Usage:
#   ./teardown.sh
#
# By default this deletes Cloud Run services and Secret Manager secrets.
# The GCS models bucket and service account are NOT deleted automatically
# because they may be shared or expensive to recreate.
# Pass --all to also remove the service account.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load .env if present ───────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

# ── Required variables ─────────────────────────────────────────────────────────
: "${GCP_PROJECT_ID:?'GCP_PROJECT_ID is required.'}"

# ── Defaults (must match deploy.sh) ───────────────────────────────────────────
GCP_REGION="${GCP_REGION:-us-central1}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-deepgram-cloud-run}"
DEEPGRAM_API_KEY_SECRET="${DEEPGRAM_API_KEY_SECRET:-deepgram-api-key}"
ENGINE_CONFIG_SECRET="deepgram-engine-config"
API_CONFIG_SECRET="deepgram-api-config"
ENGINE_SERVICE_NAME="${ENGINE_SERVICE_NAME:-deepgram-engine}"
API_SERVICE_NAME="${API_SERVICE_NAME:-deepgram-api}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

DELETE_SA=false
if [[ "${1:-}" == "--all" ]]; then
  DELETE_SA=true
fi

log()  { echo "  [teardown] $*"; }
step() { echo; echo "▶ $*"; }

# ── Confirmation ───────────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  This will DELETE the following resources in project: ${GCP_PROJECT_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cloud Run services: ${API_SERVICE_NAME}, ${ENGINE_SERVICE_NAME}"
echo "  Secrets: ${DEEPGRAM_API_KEY_SECRET}, ${ENGINE_CONFIG_SECRET}, ${API_CONFIG_SECRET}"
if [[ "${DELETE_SA}" == "true" ]]; then
  echo "  Service account: ${SERVICE_ACCOUNT_EMAIL}"
fi
echo "  GCS models bucket: NOT deleted (delete manually if desired)"
echo

read -rp "  Proceed? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

gcloud config set project "${GCP_PROJECT_ID}" --quiet

# ── Delete Cloud Run services ──────────────────────────────────────────────────
step "Deleting Cloud Run services"
for svc in "${API_SERVICE_NAME}" "${ENGINE_SERVICE_NAME}"; do
  if gcloud run services describe "${svc}" \
      --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
    gcloud run services delete "${svc}" \
      --region="${GCP_REGION}" \
      --project="${GCP_PROJECT_ID}" \
      --quiet
    log "Deleted service: ${svc}"
  else
    log "Service not found (skipping): ${svc}"
  fi
done

# ── Delete secrets ─────────────────────────────────────────────────────────────
step "Deleting Secret Manager secrets"
for secret in "${DEEPGRAM_API_KEY_SECRET}" "${ENGINE_CONFIG_SECRET}" "${API_CONFIG_SECRET}"; do
  if gcloud secrets describe "${secret}" \
      --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
    gcloud secrets delete "${secret}" \
      --project="${GCP_PROJECT_ID}" \
      --quiet
    log "Deleted secret: ${secret}"
  else
    log "Secret not found (skipping): ${secret}"
  fi
done

# ── Optionally delete service account ─────────────────────────────────────────
if [[ "${DELETE_SA}" == "true" ]]; then
  step "Deleting service account: ${SERVICE_ACCOUNT_EMAIL}"
  if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" \
      --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null; then
    gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" \
      --project="${GCP_PROJECT_ID}" \
      --quiet
    log "Deleted service account."
  else
    log "Service account not found (skipping)."
  fi
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Teardown complete."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Note: the GCS models bucket was not deleted."
echo "  To delete it: gsutil -m rm -r gs://${DEEPGRAM_MODELS_BUCKET:-YOUR_BUCKET}"
echo
