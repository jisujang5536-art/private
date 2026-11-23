# This project's settings, kept in git. Change a value, commit and push to main, and
# GitHub Actions plans and applies it (scripts/infra.sh). Every setting: variables.tf

project_id = "sonic-passkey-515610-c6"

# This repository's numeric ID. Google Cloud accepts GitHub's sign-in only from this repository
github_repo_id = "1468614875"

# Who may run events at /admin
admin_emails = ["jisujang5536@gmail.com"]

# GitHub Actions gets its own Terraform account and applies infra/ on each push that changes it
terraform_in_ci = true

# This folder is the app. The foundation (accounts, grants, sign-in) is in infra/bootstrap, which
# you apply yourself, so the account that GitHub Actions uses cannot change who may do what
layer = "app"

# ---------- Lab changes (docs/terraform-lab.ko.md) ----------

# 1. Cold start. 0: with no requests, no instance runs, and the next visitor waits while one starts.
#    1: one instance always waits, billed while idle. Put it back to 0 after the lab
web_min_instances = 0
