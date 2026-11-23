# Terraform and GitOps lab quickstart

Build the whole Cloud Ticketing system in a new Google Cloud project with Terraform, then change one setting through git: minimum instances (최소 인스턴스), which removes the cold start (콜드 스타트). The step-by-step guide with explanations: [terraform-lab.en.md](terraform-lab.en.md). 한국어: [terraform-quickstart.ko.md](terraform-quickstart.ko.md).

Files are edited in the **Cloud Shell Editor**, commands run in the **Cloud Shell terminal**, and **GitHub** means the website in your browser (review, merge, revert). The two `./lab` commands are the only lab scripts, for the one-time setup; everything after uses terraform, git, gcloud, curl and GitHub. You need a project with billing linked, a GitHub account and Cloud Shell. Setup takes about 30 minutes; the cold-start check needs two 15-minute idle waits.

## 1. Set up (once)

1. **Console:** create a project and link billing. **GitHub:** open `joyrla/gdgoc-tickets-lab` → **Use this template** → a private repository named `gdgoc-tickets-iac`.
2. **Cloud Shell terminal** (**Activate Cloud Shell**, >_ at the top right of the Console): sign in to GitHub, get your copy, and connect it to the project.

   ```bash
   gh auth login --hostname github.com --git-protocol https --web --scopes workflow   # code at github.com/login/device
   gh repo clone YOUR_GITHUB_ID/gdgoc-tickets-iac     # your private copy
   cd gdgoc-tickets-iac
   ./lab bootstrap PROJECT_ID                         # Terraform 1.9.8, two settings files, state bucket (상태 버킷), init
   source ~/.bashrc                                   # once: this terminal now finds Terraform (Cloud Shell no longer ships it)
   ```

3. **Cloud Shell terminal: build the foundation** (기반: APIs, service accounts, roles, GitHub's keyless sign-in). It decides who may do what, so you apply it yourself.

   ```bash
   cd infra/bootstrap
   terraform plan     # read it first: Plan: 55 to add, 0 to change, 0 to destroy.
   terraform apply    # shows the plan again; type yes. About 2 minutes
   ```

4. **Cloud Shell terminal: hand the app to GitHub Actions** (GitOps: the settings in git are the desired state). The first push builds the app with Terraform, with an account that cannot change IAM, then deploys.

   ```bash
   cd ../..
   ./lab connect                                      # GitHub Actions variables, deploys on
   git add infra/terraform.tfvars infra/bootstrap/terraform.tfvars
   git commit -m "Terraform settings for my project"
   git push                                           # Actions: Plan: 51 to add, apply, then the app deploys (about 20 minutes)
   terraform -chdir=infra output -raw web_url         # the site's address, once the run has finished
   ```

   In a new project the `infra` job may print a warning (Eventarc or Firestore not ready yet), then apply what is left by itself a minute later. If the job still fails: on GitHub, the run → **Re-run jobs** → **Re-run failed jobs**.

## 2. The cold start in one line of Terraform

**Where plan and apply run from now on**
- **Pull request:** GitHub Actions plans with a read-only account and posts the plan as a comment. Nothing changes yet.
- **Merge to `main`:** GitHub Actions plans again, stops if anything would be destroyed, then applies.
- **Cloud Shell:** the foundation's apply (section 1, step 3), and `terraform -chdir=infra plan` whenever you want a preview.

| Step | Where: do | What you should see |
|---|---|---|
| Measure | **Cloud Shell terminal:** leave the site idle for 15+ minutes, then `URL=$(terraform -chdir=infra output -raw web_url)`, then `for i in 1 2 3; do curl -s -o /dev/null -w '%{time_total}s  %header{x-served-by}\n' "$URL/health"; done` | First request about 4–6 s, then about 0.1 s |
| Branch | **Cloud Shell terminal:** `git switch main && git pull`, then `git switch -c min-instances-1` | |
| Change | **Cloud Shell Editor:** `infra/terraform.tfvars` → `web_min_instances = 1` → save (Ctrl+S) | `git diff` in the terminal shows `0` → `1` |
| Preview | **Cloud Shell terminal:** `terraform -chdir=infra plan` | `Plan: 0 to add, 1 to change, 0 to destroy.` (nothing is applied) |
| Pull request | **Cloud Shell terminal:** `git commit -am "web: keep one instance warm"`, `git push -u origin min-instances-1`, `gh pr create --fill` | The pull request's address |
| Review | **GitHub:** wait 1–2 minutes for the plan comment on the pull request | `Plan: 0 to add, 1 to change, 0 to destroy.` The housekeeping job's `WEB_MIN_INSTANCES` goes from "0" to "1"; "This plan destroys nothing" |
| Apply | **GitHub:** **Merge pull request** → Confirm merge. Then, in the Cloud Shell terminal, `git switch main && git pull` | Actions: checks, plan, destroy check, apply. Build and deploy skipped (about 3 minutes) |
| Apply now | **Cloud Shell terminal:** `gcloud run jobs execute housekeeping --region asia-northeast3 --wait`, or Console → Cloud Run → Jobs → `housekeeping` → Execute (otherwise within 5 minutes) | |
| Check | **Cloud Shell terminal:** `gcloud run services describe web --region asia-northeast3 --format=yaml \| grep minScale` | `run.googleapis.com/minScale: '1'` (service level; the `autoscaling.knative.dev` line is the revision's own value) |
| Measure again | **Cloud Shell terminal:** idle for 15+ minutes, then the same `curl` loop | First request about 0.1 s, from the same instance |
| Drift | **Console:** Cloud Run → Jobs → `housekeeping` → Edit → Variables & Secrets → `PREWARM_INSTANCES` = `6` → Update (on-call warmed up by hand for a big event). Then **Cloud Shell terminal:** `terraform -chdir=infra plan` | `PREWARM_INSTANCES` `"6"` → `"3"`, `1 to change`: a change made outside Terraform (드리프트), which the next apply undoes |
| Undo | **GitHub:** on the merged pull request, **Revert** → Create pull request → read the plan → Merge | The plan changes two values: `WEB_MIN_INSTANCES` `"1"` → `"0"` (the undo) and `PREWARM_INSTANCES` `"6"` → `"3"` (the drift). To keep 6, it would go into `infra/terraform.tfvars` (`prewarm`) in this pull request; here, merge. Minimum instances (최소 인스턴스) are billed while idle |

**Why the plan changes a job, not the web service.** The housekeeping job runs every 5 minutes and sets web's minimum instances: 3 from 15 minutes before a signup opening, `web_min_instances` otherwise. Terraform passes it the value and ignores that field on the service (`ignore_changes` in `run.tf`), because two owners of one setting would overwrite each other.

## 3. Clean up

First check on GitHub, in **Actions**, that the undo's run has finished (destroying during a run fails on the state lock). Then, in the Cloud Shell terminal:

```bash
gh variable delete DEPLOY_ENABLED            # deploys off, so no later push deploys to a deleted project
terraform -chdir=infra destroy               # the app: 51 to destroy. Type yes; about 7 minutes
terraform -chdir=infra/bootstrap destroy     # then the foundation: 55 to destroy. About 2 minutes
```

The state bucket `PROJECT_ID-tfstate` stays, because it was made outside Terraform. Delete it in Cloud Storage if you no longer need it.
