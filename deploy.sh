#!/usr/bin/env bash
# Deploy the NJ Transit MCP server to Cloud Run.
#
# Prerequisites (one-time):
#   gcloud auth login
#   gcloud config set project YOUR_PROJECT
#   gcloud services enable run.googleapis.com secretmanager.googleapis.com artifactregistry.googleapis.com
#
#   # Store NJT credentials in Secret Manager:
#   printf %s "$NJTRANSIT_USERNAME" | gcloud secrets create njtransit-username --data-file=-
#   printf %s "$NJTRANSIT_PASSWORD" | gcloud secrets create njtransit-password --data-file=-
#
# Then run: ./deploy.sh

set -euo pipefail

: "${PROJECT_ID:?set PROJECT_ID}"
: "${REGION:=us-east4}"
SERVICE="${SERVICE:-njtransit-mcp}"
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE}:latest"

gcloud builds submit --tag "${IMAGE}" --project "${PROJECT_ID}"

# Grant the default Compute service account access to both secrets.
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for secret in njtransit-username njtransit-password; do
  gcloud secrets add-iam-policy-binding "${secret}" \
    --member="serviceAccount:${SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${PROJECT_ID}"
done

gcloud run deploy "${SERVICE}" \
  --image "${IMAGE}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --set-secrets "NJTRANSIT_USERNAME=njtransit-username:latest,NJTRANSIT_PASSWORD=njtransit-password:latest"

gcloud run services describe "${SERVICE}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --format='value(status.url)'
