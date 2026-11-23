output "service_accounts" {
  description = "Each job's service account email, through the resource when this module made it"
  value       = { for k, email in local.sa_email : k => try(google_service_account.sa[k].email, email) }
}

output "web_scaler_role" {
  description = "The custom role that lets housekeeping change web's scaling"
  value       = try(google_project_iam_custom_role.web_scaler[0].id, "projects/${var.project_id}/roles/webScaler")
}

output "terraform_plan_sa" {
  description = "The read-only account that plans pull requests (null without terraform_in_ci)"
  value       = one(google_service_account.terraform_plan[*].email)
}

# Paste into GitHub: Settings → Secrets and variables → Actions → Variables.
# In the hand-built lab, students build the trust by hand, and ./lab env github prints these from it.
output "github_variables" {
  description = "GitHub Actions variables for keyless deploys (connect-github.sh sets them). None are secret"
  value = merge(
    {
      GCP_PROJECT_ID = var.project_id
      GCP_REGION     = var.region
      GAR_REPOSITORY = "gdgoc-tickets"
      WIF_PROVIDER   = try(google_iam_workload_identity_pool_provider.github[0].name, "${local.pool}/providers/gdgoc-tickets")
      DEPLOYER_SA    = local.sa_email["deployer"]
      # With production_extras, a fixable HIGH or CRITICAL problem in the image stops the deploy (ci.yml)
      PRODUCTION_EXTRAS = tostring(var.production_extras)
    },
    { for sa in google_service_account.terraform : "TERRAFORM_SA" => sa.email },
    # Pull requests' plans: their own keyless login and a read-only account
    { for sa in google_service_account.terraform_plan : "TERRAFORM_PLAN_SA" => sa.email },
    { for provider in google_iam_workload_identity_pool_provider.github_pr : "WIF_PR_PROVIDER" => provider.name },
  )
}
