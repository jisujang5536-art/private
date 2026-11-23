variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Region of the image registry. Same as infra/terraform.tfvars"
  type        = string
  default     = "asia-northeast3"
}

variable "github_repo_id" {
  description = "Its numeric id: gh api repos/OWNER/NAME -q .id"
  type        = string
}

variable "production_extras" {
  description = "Same as infra/terraform.tfvars: the extras' APIs and roles"
  type        = bool
  default     = false
}
