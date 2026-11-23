# Plans the configuration for each stage of the lab against a pretend Google Cloud,
# so a part that refers to a piece students build by hand fails here, not in class.
# The foundation's own pieces (accounts, grants, sign-in) are tested in foundation.tftest.hcl.
#   cd infra && terraform init -backend=false && terraform test

mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
}

mock_provider "random" {}

# Every setting is named here, so a terraform.tfvars in infra/ changes nothing
variables {
  project_id        = "student-project"
  github_repo_id    = "1000"
  admin_emails      = ["student@example.com"]
  staff_emails      = []
  alert_email       = ""
  extra_web_hosts   = []
  google_client_id  = ""
  web_service_name  = "web"
  mail_enabled      = false
  production_extras = false
  terraform_in_ci   = false
  web_min_instances = 0
  lab_parts         = null
  lab_image_tag     = "lab"
  layer             = "all"
}

run "production_builds_everything" {
  command = plan
  variables {
    production_extras = true
  }
  assert {
    condition     = google_firestore_database.main[0].delete_protection_state == "DELETE_PROTECTION_ENABLED" && google_firestore_database.main[0].point_in_time_recovery_enablement == "POINT_IN_TIME_RECOVERY_ENABLED"
    error_message = "Production keeps Firestore delete protection and point-in-time recovery."
  }
  assert {
    condition     = length(google_cloud_run_v2_service.svc) == 3 && length(google_cloud_run_v2_job.housekeeping) == 1
    error_message = "Production should build all three services and the job."
  }
  assert {
    condition     = length(google_pubsub_subscription.ticket_worker[0].push_config) == 1
    error_message = "Production's ticket-worker subscription should push."
  }
  assert {
    condition     = google_pubsub_subscription.dead_letter[0].ack_deadline_seconds == 60
    error_message = "A pulled but unacked dead letter should come back within a minute."
  }
  assert {
    condition     = length(module.foundation) == 1 && contains(keys(output.github_variables), "TERRAFORM_SA")
    error_message = "Production applies the foundation from infra/, with CI's Terraform account."
  }
}

# The Terraform session (docs/terraform-lab.ko.md): the whole system, applied by CI, without the extras
run "terraform_in_ci_without_extras" {
  command = plan
  variables {
    terraform_in_ci = true
  }
  assert {
    condition     = google_firestore_database.main[0].delete_protection_state == "DELETE_PROTECTION_DISABLED" && length(google_monitoring_uptime_check_config.web) == 0
    error_message = "The extras stay off, so terraform destroy can remove the lab."
  }
  assert {
    condition     = length(google_cloud_run_v2_service.svc) == 3 && length(google_cloud_run_v2_job.housekeeping) == 1
    error_message = "The whole system is built."
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.terraform_plan_reads_generated) == 2
    error_message = "A pull request's plan reads the two generated secrets."
  }
}

# The Terraform lab's split: a person applies the foundation (infra/bootstrap), CI applies this
run "split_app_layer" {
  command = plan
  variables {
    terraform_in_ci = true
    layer           = "app"
  }
  assert {
    condition     = length(module.foundation) == 0 && output.github_variables == null
    error_message = "The app layer leaves the foundation to infra/bootstrap."
  }
  assert {
    condition     = google_cloud_run_v2_service.svc["web"].template[0].service_account == "tickets-web@student-project.iam.gserviceaccount.com" && google_cloud_run_v2_job.housekeeping[0].template[0].template[0].service_account == "tickets-housekeeping@student-project.iam.gserviceaccount.com"
    error_message = "The app runs as the foundation's accounts, found by name."
  }
  assert {
    condition     = google_cloud_run_v2_service_iam_member.housekeeping_updates_web[0].role == "projects/student-project/roles/webScaler"
    error_message = "housekeeping gets the foundation's custom role on web."
  }
  assert {
    condition     = alltrue([for grant in google_secret_manager_secret_iam_member.terraform_plan_reads_generated : grant.member == "serviceAccount:tickets-terraform-plan@student-project.iam.gserviceaccount.com"]) && length(google_secret_manager_secret_iam_member.terraform_plan_reads_generated) == 2
    error_message = "The pull-request account reads the generated secrets."
  }
  assert {
    condition     = length(google_cloud_run_v2_service.svc) == 3 && length(google_eventarc_trigger.registration_changed) == 1 && length(google_cloud_scheduler_job.housekeeping) == 1
    error_message = "The app layer builds the whole app."
  }
}

run "lab_start" {
  command = plan
  variables {
    lab_parts = ["start"]
  }
  assert {
    condition     = length(module.foundation) == 1 && length(google_firestore_database.main) == 0 && length(google_cloud_run_v2_service.svc) == 0
    error_message = "start builds the registry (in the foundation) and nothing students build later."
  }
}

run "lab_base_after_firestore_by_hand" {
  command = plan
  variables {
    lab_parts = ["start", "base"]
  }
  assert {
    condition     = length(google_firestore_database.main) == 0 && length(google_firestore_field.ttl) == 5
    error_message = "base adds the expiry rules to the database students made, without owning it."
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.access) == 0
    error_message = "web's secret access is the student's step 5 grant."
  }
}

run "lab_workers_after_topics_and_web_by_hand" {
  command = plan
  variables {
    lab_parts = ["start", "base", "workers"]
  }
  assert {
    condition     = toset(keys(google_cloud_run_v2_service.svc)) == toset(["ticket-worker", "waitlist-promoter"])
    error_message = "workers deploys the two workers, not web."
  }
  assert {
    condition     = google_cloud_run_v2_service.svc["ticket-worker"].template[0].containers[0].image == "asia-northeast3-docker.pkg.dev/student-project/gdgoc-tickets/ticket-worker:lab"
    error_message = "The workers start on the images Cloud Build made."
  }
  assert {
    condition     = google_pubsub_subscription.mailer[0].topic == "projects/student-project/topics/emails"
    error_message = "mailer subscribes to the emails topic the student made."
  }
  assert {
    condition     = toset(keys(google_secret_manager_secret_iam_member.access)) == toset(["ticket-worker/ticket-secret"])
    error_message = "workers grants only ticket-worker's secret."
  }
  assert {
    condition     = length(google_pubsub_subscription.ticket_worker) == 0 && length(google_eventarc_trigger.registration_changed) == 0
    error_message = "Hand-built pieces stay out of Terraform."
  }
}

run "lab_skip_topics_makes_pull" {
  command = plan
  variables {
    lab_parts = ["start", "base", "topics"]
  }
  assert {
    condition     = length(google_pubsub_subscription.ticket_worker[0].push_config) == 0
    error_message = "Step 4 makes a Pull subscription."
  }
}

run "lab_skip_push" {
  command = plan
  variables {
    lab_parts = ["start", "base", "topics", "workers", "push"]
  }
  assert {
    condition     = google_pubsub_subscription.ticket_worker[0].push_config[0].oidc_token[0].service_account_email == "tickets-pubsub-push@student-project.iam.gserviceaccount.com"
    error_message = "Step 8 signs each push as tickets-pubsub-push."
  }
}

run "lab_warmup_with_web_by_hand" {
  command = plan
  variables {
    lab_parts = ["start", "base", "workers", "warmup"]
  }
  assert {
    condition     = google_cloud_run_v2_service_iam_member.housekeeping_updates_web[0].name == "web"
    error_message = "warmup applies to the web service the student deployed."
  }
}

run "lab_skip_everything" {
  command = plan
  variables {
    lab_parts = ["start", "database", "base", "topics", "web", "workers", "push", "eventarc", "schedule", "warmup", "trust", "deployer"]
  }
  assert {
    condition     = google_cloud_run_v2_job.housekeeping[0].template[0].template[0].containers[0].image == "asia-northeast3-docker.pkg.dev/student-project/gdgoc-tickets/housekeeping:lab"
    error_message = "The job starts on its Cloud Build image."
  }
  assert {
    condition     = output.github_variables.DEPLOYER_SA == "tickets-deployer@student-project.iam.gserviceaccount.com"
    error_message = "./lab env github prints the deployer's account."
  }
}

run "lab_deployer_with_trust_by_hand" {
  command = plan
  variables {
    lab_parts = ["start", "base", "workers", "warmup", "deployer"]
  }
  assert {
    condition     = output.github_variables.WIF_PROVIDER == "projects/123456789012/locations/global/workloadIdentityPools/github/providers/gdgoc-tickets"
    error_message = "With a hand-built trust, the provider's name follows the names in the sheet."
  }
}

run "lab_parts_rejects_unknown_part" {
  command = plan
  variables {
    lab_parts = ["start", "typo"]
  }
  expect_failures = [var.lab_parts]
}
