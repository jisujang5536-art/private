# Bot protection for signup: reCAPTCHA Enterprise, score-based (invisible).
# The page asks Google for a token, the web service asks Google for a score
# (shared/guard.py). Free up to 10,000 assessments a month.

locals {
  # Cloud Run's predictable address for web, plus any other hostname of it
  web_hosts = concat(["${var.web_service_name}-${data.google_project.this.number}.${var.region}.run.app"], var.extra_web_hosts)
}

resource "google_recaptcha_enterprise_key" "signup" {
  count        = var.production_extras ? 1 : 0
  display_name = "gdgoc-tickets signup"

  web_settings {
    integration_type  = "SCORE"
    allowed_domains   = local.web_hosts
    allow_amp_traffic = false
  }

  depends_on = [module.foundation]
}

# web's role to ask for a score is in the foundation (modules/foundation/iam.tf)
