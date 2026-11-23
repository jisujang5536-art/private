# The foundation (modules/foundation): the APIs, the image registry, one service account per job,
# every grant on the project or on one of those accounts, GitHub's keyless sign-in and CI's
# Terraform accounts. Everything else in this folder is the app, and refers to them by name.
#
#   layer = "all"  production and the hand-built lab: this folder applies the foundation too
#   layer = "app"  the Terraform lab: a person applies the foundation from infra/bootstrap, and
#                  GitHub Actions applies this folder with roles that cannot change IAM

module "foundation" {
  count  = var.layer == "all" ? 1 : 0
  source = "./modules/foundation"

  project_id        = var.project_id
  project_number    = data.google_project.this.number
  region            = var.region
  github_repo_id    = var.github_repo_id
  production_extras = var.production_extras
  terraform_in_ci   = var.terraform_in_ci
  lab               = local.lab
  on                = local.on
}

locals {
  # One service account per job (modules/foundation/main.tf)
  service_account_names = ["web", "ticket-worker", "waitlist-promoter", "housekeeping", "pubsub-push", "eventarc", "scheduler", "deployer"]
}

# These resources moved into the foundation module. Without these blocks, Terraform would delete
# the ones a state made before the move holds and create new ones.

moved {
  from = google_project_service.apis
  to   = module.foundation[0].google_project_service.apis
}

moved {
  from = google_artifact_registry_repository.images
  to   = module.foundation[0].google_artifact_registry_repository.images
}

moved {
  from = google_service_account.sa
  to   = module.foundation[0].google_service_account.sa
}

moved {
  from = google_project_iam_member.firestore
  to   = module.foundation[0].google_project_iam_member.firestore
}

moved {
  from = google_project_iam_member.eventarc_receiver
  to   = module.foundation[0].google_project_iam_member.eventarc_receiver
}

moved {
  from = google_project_iam_custom_role.web_scaler
  to   = module.foundation[0].google_project_iam_custom_role.web_scaler
}

moved {
  from = google_service_account_iam_member.housekeeping_acts_as_web
  to   = module.foundation[0].google_service_account_iam_member.housekeeping_acts_as_web
}

moved {
  from = google_project_iam_member.web_assesses_recaptcha
  to   = module.foundation[0].google_project_iam_member.web_assesses_recaptcha
}

moved {
  from = google_iam_workload_identity_pool.github
  to   = module.foundation[0].google_iam_workload_identity_pool.github
}

moved {
  from = google_iam_workload_identity_pool_provider.github
  to   = module.foundation[0].google_iam_workload_identity_pool_provider.github
}

moved {
  from = google_service_account_iam_member.github_is_deployer
  to   = module.foundation[0].google_service_account_iam_member.github_is_deployer
}

moved {
  from = google_artifact_registry_repository_iam_member.deployer_pushes
  to   = module.foundation[0].google_artifact_registry_repository_iam_member.deployer_pushes
}

moved {
  from = google_project_iam_member.deployer_deploys
  to   = module.foundation[0].google_project_iam_member.deployer_deploys
}

moved {
  from = google_service_account_iam_member.deployer_acts_as
  to   = module.foundation[0].google_service_account_iam_member.deployer_acts_as
}

moved {
  from = google_service_account.terraform
  to   = module.foundation[0].google_service_account.terraform
}

moved {
  from = google_service_account_iam_member.github_is_terraform
  to   = module.foundation[0].google_service_account_iam_member.github_is_terraform
}

moved {
  from = google_project_iam_member.terraform
  to   = module.foundation[0].google_project_iam_member.terraform
}

moved {
  from = google_iam_workload_identity_pool.github_pr
  to   = module.foundation[0].google_iam_workload_identity_pool.github_pr
}

moved {
  from = google_iam_workload_identity_pool_provider.github_pr
  to   = module.foundation[0].google_iam_workload_identity_pool_provider.github_pr
}

moved {
  from = google_service_account.terraform_plan
  to   = module.foundation[0].google_service_account.terraform_plan
}

moved {
  from = google_service_account_iam_member.github_pr_is_terraform_plan
  to   = module.foundation[0].google_service_account_iam_member.github_pr_is_terraform_plan
}

moved {
  from = google_project_iam_member.terraform_plan
  to   = module.foundation[0].google_project_iam_member.terraform_plan
}

moved {
  from = google_storage_bucket_iam_member.terraform_plan_reads_state
  to   = module.foundation[0].google_storage_bucket_iam_member.terraform_plan_reads_state
}
