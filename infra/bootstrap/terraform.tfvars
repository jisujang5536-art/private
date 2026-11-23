# The foundation's settings, kept in git: the APIs, the image registry, every service account and
# grant on the project, and GitHub's keyless sign-in. You apply this folder (terraform apply here);
# GitHub Actions applies only infra/, the app. Every setting: variables.tf

project_id = "sonic-passkey-515610-c6"

# This repository's numeric ID. Google Cloud accepts GitHub's sign-in only from this repository
github_repo_id = "1468614875"
