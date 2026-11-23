# Plans the foundation (modules/foundation) on its own: as infra/bootstrap calls it (the Terraform
# lab's split), and as infra/ calls it for production and the hand-built lab.
#   cd infra && terraform init -backend=false && terraform test

mock_provider "google" {}

# Every setting is named here
variables {
  project_id        = "student-project"
  project_number    = "123456789012"
  region            = "asia-northeast3"
  github_repo_id    = "1000"
  production_extras = false
  terraform_in_ci   = false
  split             = false
  lab               = false
  on                = {}
}

run "production" {
  command = plan
  module {
    source = "./modules/foundation"
  }
  variables {
    production_extras = true
  }
  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.github[0].attribute_condition, "assertion.event_name")
    error_message = "Production's GitHub sign-in accepts only push and workflow_dispatch runs."
  }
  assert {
    condition     = contains(keys(google_project_iam_member.terraform), "roles/monitoring.admin") && contains(keys(google_project_iam_member.terraform), "roles/resourcemanager.projectIamAdmin")
    error_message = "Production's CI account applies everything in infra/, the monitoring it adds included."
  }
  assert {
    condition     = length(google_project_iam_member.web_assesses_recaptcha) == 1
    error_message = "web may ask reCAPTCHA for a score."
  }
}

# One root applied by CI (terraform_in_ci without the split): CI's account can change IAM
run "terraform_in_ci_one_root" {
  command = plan
  module {
    source = "./modules/foundation"
  }
  variables {
    terraform_in_ci = true
  }
  assert {
    condition     = length(google_service_account.terraform) == 1 && length(google_service_account_iam_member.github_is_terraform) == 1
    error_message = "terraform_in_ci gives GitHub Actions its own Terraform account."
  }
  assert {
    condition     = length(google_project_iam_member.terraform) == 14 && !contains(keys(google_project_iam_member.terraform), "roles/monitoring.admin")
    error_message = "Without production_extras, the CI account gets no monitoring, logging or reCAPTCHA roles."
  }
  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.github[0].attribute_condition, "assertion.event_name")
    error_message = "A login that can apply Terraform accepts only push and workflow_dispatch runs."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github_pr[0].attribute_condition == "assertion.repository_id == '1000' && assertion.event_name == 'pull_request'"
    error_message = "Pull requests sign in through their own provider, and only from the student's repository."
  }
  assert {
    condition     = toset(keys(google_project_iam_member.terraform_plan)) == toset(["roles/viewer", "roles/iam.securityReviewer"])
    error_message = "The pull-request account only reads."
  }
  assert {
    condition     = length(google_artifact_registry_repository_iam_member.terraform_reads_images) == 0
    error_message = "With one application, CI's account is the registry's admin already."
  }
  assert {
    condition     = google_storage_bucket_iam_member.terraform_plan_reads_state[0].role == "roles/storage.objectViewer" && google_storage_bucket_iam_member.terraform_plan_reads_state[0].bucket == "student-project-tfstate"
    error_message = "A pull request's plan reads the state."
  }
}

# The Terraform lab's split (infra/bootstrap): a person applies this, CI applies only the app
run "split" {
  command = plan
  module {
    source = "./modules/foundation"
  }
  variables {
    terraform_in_ci = true
    split           = true
  }
  assert {
    condition = toset(keys(google_project_iam_member.terraform)) == toset([
      "roles/browser", "roles/cloudscheduler.admin", "roles/datastore.owner", "roles/eventarc.admin",
      "roles/iam.serviceAccountUser", "roles/pubsub.admin", "roles/run.admin", "roles/secretmanager.admin",
      "roles/serviceusage.serviceUsageConsumer", "roles/storage.admin",
    ])
    error_message = "In the split, CI's account gets the app's roles only: none that change IAM, accounts, roles, logins or APIs."
  }
  assert {
    condition     = length(google_service_account.sa) == 8 && length(google_artifact_registry_repository.images) == 1 && length(google_project_iam_custom_role.web_scaler) == 1
    error_message = "The foundation holds every account, the registry CI pushes to, and the custom role."
  }
  assert {
    condition     = length(google_artifact_registry_repository_iam_member.deployer_pushes) == 1 && length(google_service_account_iam_member.deployer_acts_as) == 4
    error_message = "The deployer can push and deploy before CI applies the app."
  }
  assert {
    condition     = google_artifact_registry_repository_iam_member.terraform_reads_images[0].role == "roles/artifactregistry.reader"
    error_message = "Cloud Run lets CI update a job or service only if CI may read its image."
  }
  assert {
    condition     = toset(keys(output.github_variables)) == toset(["GCP_PROJECT_ID", "GCP_REGION", "GAR_REPOSITORY", "WIF_PROVIDER", "DEPLOYER_SA", "PRODUCTION_EXTRAS", "TERRAFORM_SA", "TERRAFORM_PLAN_SA", "WIF_PR_PROVIDER"])
    error_message = "./lab connect gets every variable CI needs from the foundation."
  }
}

run "lab_start" {
  command = plan
  module {
    source = "./modules/foundation"
  }
  variables {
    lab = true
    on  = { start = true, base = false, workers = false, warmup = false, trust = false, deployer = false }
  }
  assert {
    condition     = length(google_artifact_registry_repository.images) == 1 && length(google_service_account.sa) == 0
    error_message = "start builds the registry and nothing students build later."
  }
  assert {
    condition     = contains(keys(google_project_service.apis), "billingbudgets.googleapis.com")
    error_message = "./lab check 0 reads the budget."
  }
}

run "lab_skip_everything" {
  command = plan
  module {
    source = "./modules/foundation"
  }
  variables {
    lab = true
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "assertion.repository_id == '1000' && assertion.ref == 'refs/heads/main'"
    error_message = "Only the student's repository, only main."
  }
}

run "lab_deployer_with_trust_by_hand" {
  command = plan
  module {
    source = "./modules/foundation"
  }
  variables {
    lab = true
    on  = { trust = false }
  }
  assert {
    condition     = length(google_service_account_iam_member.github_is_deployer) == 0 && length(google_project_iam_member.deployer_deploys) == 1
    error_message = "The repository's act-as on the deployer is the student's grant; the deployer's roles are ./lab's."
  }
}
