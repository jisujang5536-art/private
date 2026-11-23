#!/usr/bin/env bash
# Give GitHub Actions what it needs to deploy: copies Terraform's outputs into
# the repository's Actions variables and turns deploys on. Nothing secret is
# stored in GitHub; the login is keyless (Workload Identity Federation), and
# terraform.tfvars holds no secrets.
#
#   ./connect-github.sh            uses the repository of the current git remote
#   ./connect-github.sh OWNER/REPO
set -euo pipefail
cd "$(dirname "$0")"

REPO=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
# Where the sign-in and the accounts are: the foundation in bootstrap/ when a person applies it
# apart from the app (./lab bootstrap), else this folder
TF_DIR=.
if [ -f bootstrap/terraform.tfvars ]; then
  TF_DIR=bootstrap
fi

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)
fi

terraform -chdir="$TF_DIR" output -json github_variables |
  python3 -c 'import json, sys; [print(k, v) for k, v in json.load(sys.stdin).items()]' |
  while read -r name value; do
    gh variable set "$name" --repo "$REPO" --body "$value"
    echo "set $name"
  done

# With a CI account for Terraform (terraform_in_ci or production_extras), CI also applies infra/
# with the same settings. It reads infra/terraform.tfvars from the repository; where the file is
# kept out of git, it gets a copy instead
if terraform -chdir="$TF_DIR" output -json github_variables | grep -q TERRAFORM_SA && git check-ignore -q terraform.tfvars; then
  gh variable set TFVARS --repo "$REPO" < terraform.tfvars
  echo "set TFVARS. After changing terraform.tfvars, run this script again"
fi

gh variable set DEPLOY_ENABLED --repo "$REPO" --body true
echo "set DEPLOY_ENABLED=true"
if git check-ignore -q terraform.tfvars; then
  echo "Deploy now with: gh workflow run ci.yml --ref main"
elif [ "$TF_DIR" = bootstrap ]; then
  echo "Next: commit infra/terraform.tfvars and infra/bootstrap/terraform.tfvars, and push. That run builds the app and deploys."
else
  echo "Next: commit infra/terraform.tfvars and push. That run deploys."
fi
