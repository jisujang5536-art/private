output "web_url" {
  description = "Public address of the web service"
  value       = try(google_cloud_run_v2_service.svc["web"].uri, local.web_url)
}

output "image_registry" {
  description = "Artifact Registry path that CI pushes the four images to"
  value       = local.registry
}

# Paste into GitHub: Settings → Secrets and variables → Actions → Variables.
# In the hand-built lab, students build the trust by hand, and ./lab env github prints these from it.
output "github_variables" {
  description = "GitHub Actions variables for keyless deploys (connect-github.sh sets them). None are secret. With layer = \"app\", infra/bootstrap outputs them"
  value       = var.layer == "all" ? module.foundation[0].github_variables : null
}

output "web_service_name" {
  description = "Name of the web Cloud Run service"
  value       = var.web_service_name
}
