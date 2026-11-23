variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "project_number" {
  description = "The project's number, part of the GitHub sign-in pool's name"
  type        = string
}

variable "region" {
  description = "Region of the image registry"
  type        = string
}

variable "github_repo_id" {
  description = "The repository's numeric id. Google Cloud accepts GitHub's sign-in only from it"
  type        = string
}

variable "production_extras" {
  description = "Also the reCAPTCHA and monitoring APIs, web's reCAPTCHA role, and CI's roles for them"
  type        = bool
  default     = false
}

variable "terraform_in_ci" {
  description = "GitHub Actions gets its own Terraform accounts: one applies pushes to main, a read-only one plans pull requests"
  type        = bool
  default     = false
}

variable "split" {
  description = "A person applies this module (infra/bootstrap) and GitHub Actions applies only the app (infra/, layer = \"app\"), so CI's account gets the app's roles and none that change IAM"
  type        = bool
  default     = false
}

variable "lab" {
  description = "The hand-built lab (lab_parts set): also the budget API that ./lab check reads"
  type        = bool
  default     = false
}

variable "on" {
  description = "Which of the lab's parts to build (infra/lab.tf). A part not named is built"
  type        = map(bool)
  default     = {}
}
