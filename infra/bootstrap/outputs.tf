# ./lab connect copies these into the repository's Actions variables (../connect-github.sh)
output "github_variables" {
  description = "GitHub Actions variables for keyless deploys and CI's Terraform. None are secret"
  value       = module.foundation.github_variables
}
