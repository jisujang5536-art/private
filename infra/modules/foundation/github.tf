# Keyless deploys from GitHub Actions (Workload Identity Federation).
# GitHub issues a short-lived token for each workflow run; Google Cloud trusts it
# only when it comes from this repository's main branch, and swaps it for the
# deployer's access. The repository is matched by its numeric id, not its name:
# a name can be deleted and registered again by someone else, an id cannot.
#
# In the hand-built lab, students build the trust by hand (step 15, part "trust") and
# ./lab deployer adds the deployer's roles (part "deployer").

resource "google_iam_workload_identity_pool" "github" {
  count                     = local.on.trust ? 1 : 0
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count                              = local.on.trust ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.github[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "gdgoc-tickets"
  display_name                       = "gdgoc-tickets repository"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
  }
  # Once CI holds the Terraform account (below), the login also accepts only the two events that
  # sign in (a push to main, a manual run), so a job that any other event starts on main cannot
  # get a token. The hand-built lab's condition stays as students type it.
  attribute_condition = join(" && ", concat(
    ["assertion.repository_id == '${var.github_repo_id}'", "assertion.ref == 'refs/heads/main'"],
    local.terraform_ci ? ["(assertion.event_name == 'push' || assertion.event_name == 'workflow_dispatch')"] : [],
  ))
}

resource "google_service_account_iam_member" "github_is_deployer" {
  count              = local.on.trust ? 1 : 0
  service_account_id = try(google_service_account.sa["deployer"].name, local.sa_name["deployer"])
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/attribute.repository_id/${var.github_repo_id}"
}

# What the deployer may do: push images, deploy new revisions, and run them as
# the runtime identities. It cannot change IAM, buckets, topics or secrets.
resource "google_artifact_registry_repository_iam_member" "deployer_pushes" {
  count      = local.on.deployer ? 1 : 0
  repository = try(google_artifact_registry_repository.images[0].name, "projects/${var.project_id}/locations/${var.region}/repositories/gdgoc-tickets")
  location   = var.region
  role       = "roles/artifactregistry.writer"
  member     = local.sa["deployer"]
}

resource "google_project_iam_member" "deployer_deploys" {
  count   = local.on.deployer ? 1 : 0
  project = var.project_id
  role    = "roles/run.developer"
  member  = local.sa["deployer"]
}

resource "google_service_account_iam_member" "deployer_acts_as" {
  for_each           = local.on.deployer ? toset(["web", "ticket-worker", "waitlist-promoter", "housekeeping"]) : []
  service_account_id = google_service_account.sa[each.value].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa["deployer"]
}

# Terraform in CI (terraform_in_ci, or production_extras): a push to main that changes
# infra/ applies it (scripts/infra.sh). The deployer can't, so this is a separate
# account, used by that one job. Without it, a person runs terraform apply by hand.
#
# What the account may do depends on what CI applies:
# - all of infra/ in one piece (layer = "all"): these roles are close to project owner, since
#   projectIamAdmin alone lets the account grant itself more. A push to main is then admin access
#   to this project, which is why the login above accepts only this repository's main branch and
#   two events. The list leaves out deleting the project.
# - only the app (split, the Terraform lab): a person applies this module, which holds every
#   account, custom role, login and grant on the project, so CI needs no role that changes IAM.
#   It may still grant access on what the app makes (a bucket, a topic, a service).
# The roles for monitoring and reCAPTCHA come only with production_extras.
locals {
  terraform_ci = var.terraform_in_ci || var.production_extras
  whole_roles = [
    "roles/artifactregistry.admin",
    "roles/cloudscheduler.admin",
    "roles/datastore.owner",
    "roles/eventarc.admin",
    "roles/iam.roleAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/pubsub.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/storage.admin", # also Terraform's state, in the bucket bootstrap-state.sh made
  ]
  app_roles = [
    "roles/browser", # reads the project, for its number
    "roles/cloudscheduler.admin",
    "roles/datastore.owner",
    "roles/eventarc.admin",
    "roles/iam.serviceAccountUser", # runs the services, the job and the trigger as their accounts
    "roles/pubsub.admin",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageConsumer", # calls the APIs this module turned on
    "roles/storage.admin",                     # also Terraform's state
  ]
  extra_roles = ["roles/logging.configWriter", "roles/monitoring.admin", "roles/recaptchaenterprise.admin"]
  terraform_roles = local.terraform_ci ? setunion(
    var.split ? local.app_roles : local.whole_roles,
    var.production_extras ? local.extra_roles : [],
  ) : toset([])
}

resource "google_service_account" "terraform" {
  count        = local.terraform_ci ? 1 : 0
  account_id   = "tickets-terraform"
  display_name = "GitHub Actions: apply infra/"
}

resource "google_service_account_iam_member" "github_is_terraform" {
  count              = local.terraform_ci ? 1 : 0
  service_account_id = google_service_account.terraform[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${try(google_iam_workload_identity_pool.github[0].name, local.pool)}/attribute.repository_id/${var.github_repo_id}"
}

resource "google_project_iam_member" "terraform" {
  for_each = local.terraform_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.terraform[0].email}"
}

# Cloud Run checks that whoever updates a service or job may read its image, and after the first
# deploy those are the deployer's images here. One application: CI's account holds the registry's
# admin role anyway; the app alone: read the images, nothing more
resource "google_artifact_registry_repository_iam_member" "terraform_reads_images" {
  count      = local.terraform_ci && var.split ? 1 : 0
  repository = try(google_artifact_registry_repository.images[0].name, "projects/${var.project_id}/locations/${var.region}/repositories/gdgoc-tickets")
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.terraform[0].email}"
}

# Pull requests: plan only (the pr-plan job in ci.yml). Their own pool, so a pull request's token
# can never reach the deployer or the Terraform account above: both trust only the github pool,
# whose login accepts nothing but pushes and manual runs on main. Forks get no token at all.
resource "google_iam_workload_identity_pool" "github_pr" {
  count                     = local.terraform_ci ? 1 : 0
  workload_identity_pool_id = "github-pr"
  display_name              = "GitHub pull requests"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github_pr" {
  count                              = local.terraform_ci ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pr[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "gdgoc-tickets-pr"
  display_name                       = "gdgoc-tickets pull requests"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository_id" = "assertion.repository_id"
  }
  attribute_condition = "assertion.repository_id == '${var.github_repo_id}' && assertion.event_name == 'pull_request'"
}

# Reads everything a plan refreshes, writes nothing: Viewer for the resources, Security Reviewer
# for their IAM policies, and the state's objects (a pull request's plan takes no lock, which would
# be a write). The app also lets it read the two generated secrets, whose values a refresh reads
# (infra/github.tf). The state holds those values too, so this account sees secrets: like the plan
# itself, it stays inside this project.
resource "google_service_account" "terraform_plan" {
  count        = local.terraform_ci ? 1 : 0
  account_id   = "tickets-terraform-plan"
  display_name = "GitHub Actions: plan infra/ on pull requests (read-only)"
}

resource "google_service_account_iam_member" "github_pr_is_terraform_plan" {
  count              = local.terraform_ci ? 1 : 0
  service_account_id = google_service_account.terraform_plan[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pr[0].name}/attribute.repository_id/${var.github_repo_id}"
}

resource "google_project_iam_member" "terraform_plan" {
  for_each = local.terraform_ci ? toset(["roles/viewer", "roles/iam.securityReviewer"]) : toset([])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.terraform_plan[0].email}"
}

resource "google_storage_bucket_iam_member" "terraform_plan_reads_state" {
  count  = local.terraform_ci ? 1 : 0
  bucket = "${var.project_id}-tfstate" # made by bootstrap-state.sh, outside Terraform
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.terraform_plan[0].email}"
}
