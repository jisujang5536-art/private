#!/usr/bin/env bash
# Move Terraform's state from this laptop into a Cloud Storage bucket.
#
# The state lists every resource, and the generated secrets in plain text. On
# a laptop it can be lost, copied, or out of date for the next person. In a
# private, versioned bucket it is shared, recoverable (old versions), and
# locked while one apply runs.
#
# The bucket is made here, not by Terraform: Terraform cannot keep its state in
# a bucket it has not created yet. Run once per project:  ./bootstrap-state.sh
#
# With bootstrap/terraform.tfvars (./lab bootstrap writes it), the foundation in bootstrap/ gets
# its own state in the same bucket, under the prefix gdgoc-tickets-bootstrap.
set -euo pipefail
cd "$(dirname "$0")"

PROJECT=$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' terraform.tfvars)
REGION=$(sed -n 's/^region *= *"\(.*\)"/\1/p' terraform.tfvars)
REGION=${REGION:-asia-northeast3}
BUCKET="$PROJECT-tfstate"

# Terraform needs the first three before it can turn on the rest (modules/foundation) or create service
# accounts. Eventarc is on here too, so ./lab bootstrap can make its service agent next: the agent
# needs minutes for its role, and a first apply that makes it builds the trigger too early
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com iam.googleapis.com \
  eventarc.googleapis.com --project "$PROJECT"

if ! gcloud storage buckets describe "gs://$BUCKET" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" \
    --uniform-bucket-level-access --public-access-prevention
fi
gcloud storage buckets update "gs://$BUCKET" --versioning --uniform-bucket-level-access --public-access-prevention   # keeps every previous state; private even if the bucket existed before
# Uniform access gives project Viewers object read by default, and the state holds the generated secrets
gcloud storage buckets remove-iam-policy-binding "gs://$BUCKET" --member="projectViewer:$PROJECT" \
  --role=roles/storage.legacyObjectReader >/dev/null 2>&1 || true

printf 'bucket = "%s"\nprefix = "gdgoc-tickets"\n' "$BUCKET" > backend.hcl

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)
fi
terraform init -input=false -migrate-state -force-copy -backend-config=backend.hcl

# The copies on this laptop still hold the secrets
rm -f terraform.tfstate terraform.tfstate.backup
echo "State is now in gs://$BUCKET/gdgoc-tickets. Next time: terraform init -backend-config=backend.hcl"

if [ -f bootstrap/terraform.tfvars ]; then
  printf 'bucket = "%s"\nprefix = "gdgoc-tickets-bootstrap"\n' "$BUCKET" > bootstrap/backend.hcl
  terraform -chdir=bootstrap init -input=false -backend-config=backend.hcl
  echo "The foundation's state: gs://$BUCKET/gdgoc-tickets-bootstrap"
fi
