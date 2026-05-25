# Deploy the NJ Transit MCP server to Cloud Run.
#
# Prerequisites (one-time):
#   gcloud auth login
#   gcloud config set project YOUR_PROJECT
#   gcloud services enable run.googleapis.com secretmanager.googleapis.com artifactregistry.googleapis.com
#
#   # Store NJT credentials in Secret Manager:
#   $env:NJTRANSIT_USERNAME | gcloud secrets create njtransit-username --data-file=-
#   $env:NJTRANSIT_PASSWORD | gcloud secrets create njtransit-password --data-file=-
#
# Then run: .\deploy.ps1

$ErrorActionPreference = "Stop"

if (-not $env:PROJECT_ID) { throw "Set `$env:PROJECT_ID before running this script." }

$Region  = if ($env:REGION)  { $env:REGION }  else { "us-east4" }
$Service = if ($env:SERVICE) { $env:SERVICE } else { "njtransit-mcp" }
$Image   = "gcr.io/$($env:PROJECT_ID)/$Service`:latest"

gcloud builds submit --tag $Image --project $env:PROJECT_ID

# Grant the default Compute service account access to both secrets.
$ProjectNumber = gcloud projects describe $env:PROJECT_ID --format="value(projectNumber)"
$SA = "$ProjectNumber-compute@developer.gserviceaccount.com"
foreach ($secret in @("njtransit-username", "njtransit-password")) {
    gcloud secrets add-iam-policy-binding $secret `
      --member="serviceAccount:$SA" `
      --role="roles/secretmanager.secretAccessor" `
      --project=$env:PROJECT_ID
}

gcloud run deploy $Service `
  --image $Image `
  --region $Region `
  --project $env:PROJECT_ID `
  --platform managed `
  --allow-unauthenticated `
  --port 8080 `
  --set-secrets "NJTRANSIT_USERNAME=njtransit-username:latest,NJTRANSIT_PASSWORD=njtransit-password:latest"

gcloud run services describe $Service `
  --region $Region `
  --project $env:PROJECT_ID `
  --format "value(status.url)"
