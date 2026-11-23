# The foundation, applied by a person: the APIs, the image registry, every service account, every
# grant on the project or on one of those accounts, GitHub's keyless sign-in and CI's accounts
# (../modules/foundation). GitHub Actions then applies the app in infra/ (layer = "app") with
# roles that cannot change any of this.
#
#   ./lab bootstrap PROJECT_ID     writes terraform.tfvars and backend.hcl here, then terraform init
#   terraform plan && terraform apply
#
# Its state is apart from the app's: same bucket, prefix gdgoc-tickets-bootstrap.

terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {}

module "foundation" {
  source = "../modules/foundation"

  project_id        = var.project_id
  project_number    = data.google_project.this.number
  region            = var.region
  github_repo_id    = var.github_repo_id
  production_extras = var.production_extras
  terraform_in_ci   = true # GitHub Actions applies the app
  split             = true
}
