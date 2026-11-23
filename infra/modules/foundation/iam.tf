# Grants on the whole project or on one service account. Grants on one bucket, topic, secret or
# service are with the app (infra/iam.tf), next to what they are on.

# Every runtime service reads and writes registrations
resource "google_project_iam_member" "firestore" {
  for_each = local.on.base ? toset(["web", "ticket-worker", "waitlist-promoter", "housekeeping"]) : []
  project  = var.project_id
  role     = "roles/datastore.user"
  member   = local.sa[each.value]
}

# Eventarc's identity receives Firestore's events (the trigger is in infra/events.tf)
resource "google_project_iam_member" "eventarc_receiver" {
  count   = local.on.workers ? 1 : 0
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = local.sa["eventarc"]
}

# Pre-warm: housekeeping changes web's minimum instances. Cloud Run has no permission per field,
# so this role is read and update, granted on the one service (infra/iam.tf)
resource "google_project_iam_custom_role" "web_scaler" {
  count       = local.on.warmup ? 1 : 0
  role_id     = "webScaler"
  title       = "Change web's scaling"
  description = "Read and update one Cloud Run service, without deploying as its service account"
  permissions = ["run.services.get", "run.services.update"]
}

# A deliberate exception to least privilege. Cloud Run asks for actAs on every service
# update, even one that changes only scaling (tested: docs/cold-start.md), and actAs
# also allows deploying as web. It is limited to this one job and this one account.
resource "google_service_account_iam_member" "housekeeping_acts_as_web" {
  count              = local.on.warmup ? 1 : 0
  service_account_id = try(google_service_account.sa["web"].name, local.sa_name["web"])
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa["housekeeping"]
}

# web asks reCAPTCHA for a score (infra/abuse.tf): create assessments, nothing else
resource "google_project_iam_member" "web_assesses_recaptcha" {
  count   = var.production_extras ? 1 : 0
  project = var.project_id
  role    = "roles/recaptchaenterprise.agent"
  member  = local.sa["web"]
}
