# GitHub Actions' keyless sign-in, the deployer's roles and CI's Terraform accounts are in the
# foundation (modules/foundation/github.tf). What stays here is a grant on something this folder makes.

locals {
  terraform_ci = var.terraform_in_ci || var.production_extras
}

# The pull requests' read-only account also reads the two generated secrets, whose values a plan's
# refresh reads. The state holds them too, so this account sees secrets: like the plan itself, it
# stays inside this project.
resource "google_secret_manager_secret_iam_member" "terraform_plan_reads_generated" {
  for_each  = local.terraform_ci ? local.generated_secrets : toset([])
  secret_id = google_secret_manager_secret.secrets[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${try(module.foundation[0].terraform_plan_sa, "tickets-terraform-plan@${var.project_id}.iam.gserviceaccount.com")}"
}
