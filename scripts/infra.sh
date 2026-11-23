#!/usr/bin/env bash
# Terraform in CI. .github/workflows/ci.yml runs one stage per step, before the deploy,
# because new code may need a new setting or permission.
#
#   changes  what does this push need? Apply infra/ if it differs from the last run whose
#            infra job succeeded; build and deploy if anything else differs from the last run
#            whose deploy succeeded. A person starting the run gets both. Comparing with the
#            last success, not the last push, means a failed apply or deploy is tried again by
#            the next push, and a run from before deploys were on doesn't count as a deploy.
#            On a pull request: plan infra/ if the pull request changes it.
#   plan     work out what would change, and save it
#   check    stop if that plan destroys or replaces anything, unless a person started
#            this run with allow_destroy after reading the plan of the run that stopped
#   apply    apply exactly what was saved
#   pr-plan  a pull request's plan, for review: read-only, so it takes no state lock
#   comment  post that plan on the pull request, or update the comment an earlier push made
#
# A deploy leaves no change for the next plan: deploy.sh tags web's candidate in a separate
# step, so gcloud doesn't name the revision (a name would show here as `revision -> null`).
#
# A failed deploy rolls back the code, not these settings, so a change here must also
# work with the version already running. A plan that destroys something needs a person:
# read it in the stopped run, then gh workflow run ci.yml --ref main -f allow_destroy=true
#
# Settings: infra/terraform.tfvars from the repository (./lab bootstrap writes it and the lab
# commits it), or, where that file stays out of git, the TFVARS variable (infra/connect-github.sh).
#
# Needs: PROJECT_ID, and GH_TOKEN for changes and comment. ALLOW_DESTROY is "true" only in a run
# a person started with allow_destroy. comment also needs PR_NUMBER and HEAD_SHA.

set -euo pipefail

cd "$(dirname "$0")/../infra"

# The commit of the last run on main in which job $1 succeeded (empty if there is none).
# A lookup that fails stops the job: guessing could skip an apply or a deploy
last_success() {
  local runs id sha succeeded
  runs=$(gh run list --workflow ci.yml --branch main --status success --limit 30 --json databaseId,headSha \
    --jq '.[] | "\(.databaseId) \(.headSha)"') || return 1
  while read -r id sha; do
    [ -n "$id" ] || continue
    succeeded=$(gh run view "$id" --json jobs --jq ".jobs[] | select(.name == \"$1\" and .conclusion == \"success\") | .name") || return 1
    if [ -n "$succeeded" ]; then
      echo "$sha"
      return
    fi
  done <<< "$runs"
}

# Whether the last infra job that ran on main failed. A failed apply can leave the cloud half
# changed even when the files match the last success (say, a revert of the change that failed),
# so the next push applies again
last_apply_failed() {
  local runs id sha result
  runs=$(gh run list --workflow ci.yml --branch main --status completed --limit 30 --json databaseId,headSha \
    --jq '.[] | "\(.databaseId) \(.headSha)"') || return 1
  while read -r id sha; do
    [ -n "$id" ] || continue
    result=$(gh run view "$id" --json jobs \
      --jq '.jobs[] | select(.name == "infra" and (.conclusion == "success" or .conclusion == "failure")) | .conclusion') || return 1
    if [ -n "$result" ]; then
      [ "$result" = failure ]
      return
    fi
  done <<< "$runs"
  return 1
}

# True if these paths changed since commit $1, or there is no commit to compare with
changed_since() {
  local last=$1
  shift
  [ -z "$last" ] || ! git cat-file -e "$last^{commit}" 2> /dev/null || ! git diff --quiet "$last" HEAD -- "$@"
}

changes() {
  local infra=true app=true applied deployed
  case "$GITHUB_EVENT_NAME" in
    push)
      applied=$(last_success infra)
      deployed=$(last_success deploy)
      changed_since "$applied" . || infra=false
      if [ "$infra" = false ] && last_apply_failed; then
        infra=true
        echo "The last apply failed, so this push applies again."
      fi
      changed_since "$deployed" ':(top)' ':(top,exclude)infra' || app=false
      ;;
    pull_request)
      # The checkout is the pull request merged into its base, so the first parent is that base
      git diff --quiet HEAD^1 HEAD -- . && infra=false
      ;;
  esac
  echo "infra=$infra" >> "$GITHUB_OUTPUT"
  echo "app=$app" >> "$GITHUB_OUTPUT"
  echo "Apply infra/: $infra. Build and deploy the app: $app."
}

init() {
  if [ ! -f terraform.tfvars ]; then
    if [ -z "${TFVARS:-}" ]; then
      echo "::error::No settings. Commit infra/terraform.tfvars (./lab bootstrap writes it), or set the TFVARS variable (infra/connect-github.sh)"
      exit 1
    fi
    printf '%s\n' "$TFVARS" > terraform.tfvars
  fi
  terraform init -input=false -lockfile=readonly -backend-config="bucket=$PROJECT_ID-tfstate" -backend-config="prefix=gdgoc-tickets"
}

plan() {
  init
  terraform plan -input=false -no-color -out=tfplan
}

pr_plan() {
  init
  terraform plan -input=false -no-color -lock=false -out=tfplan
  terraform show -no-color tfplan > plan.txt
}

# A replacement is a delete plus a create, so it counts
check() {
  local destroyed
  destroyed=$(terraform show -json tfplan | jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | .address')
  if [ -z "$destroyed" ]; then
    echo "This plan destroys nothing."
  elif [ "${ALLOW_DESTROY:-}" = true ]; then
    echo "::warning::This plan destroys or replaces resources. A person allowed it (allow_destroy):"
    echo "$destroyed"
  else
    echo "::error::This plan destroys or replaces resources, so CI stops. Read the plan, then run: gh workflow run ci.yml --ref main -f allow_destroy=true"
    echo "$destroyed"
    exit 1
  fi
}

# A new project's first apply can trip on two things Google finishes setting up in the background.
# What else the plan held is applied by then, so CI waits a minute, plans what is left, checks it,
# and applies that, at most twice (every dry run got past both this way):
# - Firestore's new database not readable yet: the provider made it, then dropped it from the state
#   ("Root object was present, but now absent"; a later run then gets 409, already exists). The
#   database is there, so it is imported first
# - Eventarc not ready for its first trigger: "Permission denied while using the Eventarc Service Agent"
apply() {
  local log tries=0
  log=$(mktemp)
  until terraform apply -input=false -no-color tfplan 2>&1 | tee "$log"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 2 ]; then
      return 1
    fi
    if grep -A3 "When applying changes to google_firestore_database.main\[0\]" "$log" | grep -q "now absent" ||
      grep -q "Error creating Database: googleapi: Error 409" "$log"; then
      echo "::warning::Firestore's new database was made but not readable yet. Importing it, then applying what is left, in a minute."
      sleep 60
      terraform import -input=false -no-color 'google_firestore_database.main[0]' "projects/$PROJECT_ID/databases/(default)"
    elif grep -q "Eventarc Service Agent" "$log"; then
      echo "::warning::Eventarc was not ready for the trigger yet. Applying what is left again in a minute."
      sleep 60
    else
      return 1
    fi
    plan
    check
  done
}

# One comment per pull request, marked so a later push updates it instead of adding another.
# The plan's text can be long; a comment holds about 65,000 characters, so its start is cut
comment() {
  local marker='<!-- terraform-plan -->' destroyed id
  destroyed=$(terraform show -json tfplan | jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | .address')
  {
    echo "$marker"
    echo "### Terraform plan for ${HEAD_SHA:0:7}"
    echo
    if [ -n "$destroyed" ]; then
      echo "**This plan destroys or replaces resources.** After the merge, CI stops before applying it until a person allows it:"
      echo
      echo '```'
      echo "$destroyed"
      echo '```'
    else
      echo "This plan destroys nothing. Merging to main plans it again and applies it."
    fi
    echo
    echo '```'
    if [ "$(wc -c < plan.txt)" -gt 60000 ]; then
      echo "… (the start is cut; the whole plan is in this run's log)"
      tail -c 60000 plan.txt
    else
      cat plan.txt
    fi
    echo '```'
  } > comment.md
  id=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" --paginate \
    --jq ".[] | select(.body | startswith(\"$marker\")) | .id" | tail -n 1)
  if [ -n "$id" ]; then
    gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -F body=@comment.md > /dev/null
    echo "Updated the plan on pull request #$PR_NUMBER."
  else
    gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" -F body=@comment.md > /dev/null
    echo "Posted the plan on pull request #$PR_NUMBER."
  fi
  cat comment.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

case "${1:-}" in
  changes | plan | check | apply | comment) "$1" ;;
  pr-plan) pr_plan ;;
  *)
    echo "usage: $0 changes|plan|check|apply|pr-plan|comment" >&2
    exit 2
    ;;
esac
