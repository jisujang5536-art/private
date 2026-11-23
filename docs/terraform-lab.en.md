# Terraform and GitOps lab

This time Terraform builds the whole Cloud Ticketing system from session 8 in a new project. The app code and the Terraform code are finished; this lab is about the Terraform workflow. You read an execution plan, apply it, change one setting, and measure how the service behaves differently.

The code has two parts, applied by different accounts. The foundation (the APIs, every service account and role, GitHub's keyless sign-in) decides who may do what, so you plan and apply it yourself in Cloud Shell. The app (the services, the database, the topics, the job) is applied by GitHub Actions, with an account that cannot change who may do what. Every change to the app goes through a pull request: GitHub Actions posts the plan on the pull request, you read it and merge, and GitHub Actions applies it. The desired state lives in git, and a tool applies it (GitOps).

All the commands on one page: [terraform-quickstart.en.md](terraform-quickstart.en.md). 한국어: [terraform-lab.ko.md](terraform-lab.ko.md).

| | |
|---|---|
| Level | Introductory (200) |
| Time | About 70 minutes, plus two 15-minute idle waits before the cold-start measurements |
| Cost | A few hundred won during the lab. One minimum instance is billed even while idle, so step 9 sets it back to 0 |
| Last checked | 2026-11-23, start to finish in a new project and a repository connected to it (pull request and revert included) |

**When you finish, you can**

- read in a plan what will be created, changed and destroyed
- explain why the state file lives in a Cloud Storage bucket (a remote backend)
- explain why the foundation and the app are applied separately, by different accounts
- propose a change as a pull request, review its plan, and apply it by merging
- compare cold start and minimum instances with your own measurements
- recognize drift (a change made outside Terraform) in a plan, and decide whether it goes into the code or git removes it

## The whole flow

| Step | What | Where |
|---|---|---|
| 0 | New project, your repository, sign-in | Console, GitHub, Cloud Shell terminal |
| 1 | Settings files, state bucket, `terraform init` (`./lab bootstrap`) | Cloud Shell terminal |
| 2, 3 | The foundation: `terraform plan`, `terraform apply` in `infra/bootstrap` | Cloud Shell terminal |
| 4 | Connect GitHub Actions; the first push builds the app and deploys it (`./lab connect`, `git push`) | Cloud Shell terminal, then GitHub |
| 5–7 | Measure the cold start, change a setting through a pull request, check | Cloud Shell terminal and Editor, GitHub, Console |
| 8 | A change made in the Console: drift | Console, Cloud Shell terminal |
| 9, 10 | Undo (**Revert**), with the drift in its plan; delete everything: the app, then the foundation (`terraform destroy`) | GitHub, Cloud Shell terminal |

**Scripts only for the one-time setup.** `./lab bootstrap` and `./lab connect` do the one-time setup (the state bucket, the settings files, the GitHub Actions connection): the part real teams also script and run once. Every step after that uses standard tools (terraform, git, gcloud, curl, GitHub), and plan and apply run either by you or by GitHub Actions.

**Each step:** Problem → Do → Expect → Where to look → Check → Why, If stuck.

## Where you work

| Place | How to open it | What you do there |
|---|---|---|
| **Console** | console.cloud.google.com, with your lab project selected at the top | Create the project, billing and budget; look at Cloud Run, its logs and its YAML |
| **Cloud Shell terminal** | **Activate Cloud Shell** (>_) at the top right of the Console | Every command in this guide. Commands start in your repository's folder, `gdgoc-tickets-iac` |
| **Cloud Shell Editor** | **Open Editor** on the Cloud Shell bar | Editing the infrastructure code (`infra/terraform.tfvars` in step 6), and reading it, such as `infra/run.tf`, while you wait |
| **GitHub** (the website) | github.com in your browser → your repository | The template copy, the **Actions** tab, the change as a pull request, **Revert** |

Every grey command box runs in the **Cloud Shell terminal** (the Editor shows the same terminal at its bottom). Files are edited in the **Cloud Shell Editor**. **GitHub** always means the website in your browser, where you review pull requests, merge and revert.

---

## Step 0. Project and repository (Console, GitHub, Cloud Shell terminal: 10 minutes)

**Problem.** Your session 8 project still has resources made by hand, and Terraform creating the same names there would fail. Start from an empty project.

**Do.**
1. **Console:** ☰ → **IAM & Admin → Manage resources** → **Create project**. Note the **Project ID**.
2. **Console:** ☰ → **Billing → My projects**: link a billing account to the new project. If the link is refused (too many projects), **Disable billing** on your session 8 project and link again.
3. **Console:** ☰ → **Billing → Budgets & alerts** → **Create budget**. Scope: the new project. Amount: KRW 12,000.
4. **GitHub:** open `joyrla/gdgoc-tickets-lab` → **Use this template** → **Create a new repository**. Name it `gdgoc-tickets-iac`, **Private**.
5. **Cloud Shell terminal:** click **Activate Cloud Shell** (>_) at the top right of the Console. In the terminal that opens, sign in to GitHub: press Enter and type the code shown into [github.com/login/device](https://github.com/login/device).

   ```bash
   gh auth login --hostname github.com --git-protocol https --web --scopes workflow
   ```

6. **Cloud Shell terminal:** get your repository. It is private, so this comes after the sign-in.

   ```bash
   gh repo clone YOUR_GITHUB_ID/gdgoc-tickets-iac
   cd gdgoc-tickets-iac
   ```

**Check.** `ls` shows `lab`, `infra` and `web`.

## Step 1. Settings files and state bucket (Cloud Shell terminal: 2 minutes)

**Problem.** Terraform needs to know what to build and where (the settings), and what it has built so far (the state). If the state lived only in Cloud Shell, GitHub Actions could not see it.

**Do** in the Cloud Shell terminal, in `gdgoc-tickets-iac`:

```bash
./lab bootstrap PROJECT_ID
source ~/.bashrc
```

**What the command does.**
0. Installs Terraform 1.9.8 in `~/bin`. Cloud Shell has not included Terraform since June 2026. `source ~/.bashrc` lets the terminal that is already open find it.
1. Writes two settings files. The foundation's, `infra/bootstrap/terraform.tfvars`: the project ID and the repository's number. The app's, `infra/terraform.tfvars`: the same two, the admin email, `terraform_in_ci = true`, `layer = "app"`, `web_min_instances = 0`.
2. Creates the state bucket `PROJECT_ID-tfstate`, with object versioning and public access prevention. The foundation and the app keep separate states in it (`gdgoc-tickets-bootstrap` and `gdgoc-tickets`).
3. Runs `terraform init` in both folders: installs the providers and points each state at the bucket.
4. Creates Eventarc's service agent, so the trigger can be built in step 4.

**Check.** The last line reads `Then, back in the top folder (cd ../..): ./lab connect`. `terraform version` shows `Terraform v1.9.8`. Read both settings files with `cat infra/bootstrap/terraform.tfvars infra/terraform.tfvars` (or open them in the Cloud Shell Editor).

**If stuck.** If `./lab bootstrap` stops with `infra/terraform.tfvars links to ~/.gdgoc-lab`, a session 8 `./lab` command ran here first. Run the `rm` command it prints, then bootstrap again.

**Why.** The state file lists every resource Terraform made, and the secret values it generated. In a bucket, Cloud Shell and GitHub Actions read the same state, only one of them can apply at a time (state locking), and earlier versions are kept.

## Step 2. The foundation's plan (Cloud Shell terminal: 5 minutes)

**Problem.** Before applying, you need to know what will be created. You start with the foundation: everything that decides who may do what.

**Do** in the Cloud Shell terminal:

```bash
cd infra/bootstrap
terraform plan
```

**Expect.** At the bottom: `Plan: 55 to add, 0 to change, 0 to destroy.`

**Where to look.** Scroll up in the terminal and find:

| Find | Read |
|---|---|
| `module.foundation.google_service_account.sa["web"]` | one service account per job; web runs as `tickets-web` |
| `module.foundation.google_iam_workload_identity_pool_provider.github[0]` | `attribute_condition` holds your repository's number, `refs/heads/main`, and the two events that may sign in |
| `module.foundation.google_project_iam_member.terraform["roles/run.admin"]` | one of the 10 project roles of `tickets-terraform`, the account GitHub Actions applies the app with. None of them changes IAM |
| `module.foundation.google_artifact_registry_repository.images[0]` | the registry the first push sends its images to |

**Why.** A plan changes nothing. It compares the code (the desired state), the state file and the real cloud.

The code is split in two, as teams split theirs. The foundation decides who may do what, and whoever applies it can grant anything, so a person applies it, rarely. The app changes often, and GitHub Actions applies it with roles that cannot change IAM: a mistake in a pull request can break the app, but it cannot give anyone more access. Each state also stays small (55 and 51 resources), under Google's guideline of about 100 per state, so plans stay fast and readable.

**If stuck.** If you see `could not find default credentials`, run `gcloud auth application-default login`, then `terraform plan` again.

## Step 3. Apply the foundation (Cloud Shell terminal: 3 minutes)

**Do** in the Cloud Shell terminal, still in `infra/bootstrap`:

```bash
terraform apply
```

The same plan appears again; type `yes` at `Enter a value:`.

**Expect.** `Apply complete! Resources: 55 added, 0 changed, 0 destroyed.` About 2 minutes.

**Check.**

```bash
terraform output github_variables
```

Nine values for GitHub Actions: the project, the registry, the two keyless logins (`WIF_PROVIDER`, `WIF_PR_PROVIDER`) and three accounts (`DEPLOYER_SA`, `TERRAFORM_SA`, `TERRAFORM_PLAN_SA`). None of them is a secret.

**If stuck.** Right after its APIs are turned on, a new project can stop because permissions have not reached everything yet (`SERVICE_DISABLED`, `Permission denied`). Wait a minute or two and run `terraform apply` again. It skips what exists and creates only the rest.

## Step 4. Connect GitHub Actions; the first push builds the app (Cloud Shell terminal, then GitHub: 20 minutes)

**Problem.** From now on, the code on GitHub is the reference, not Cloud Shell. GitHub Actions has to sign in to your project, build the app from the code, and deploy it.

**Do** in the Cloud Shell terminal:

```bash
cd ../..
./lab connect
git add infra/terraform.tfvars infra/bootstrap/terraform.tfvars
git commit -m "Terraform settings for my project"
git push
```

`./lab connect` copies the foundation's outputs into the repository's variables (**Settings → Secrets and variables → Actions → Variables**) and turns deploys on (`DEPLOY_ENABLED`). No secret goes into GitHub: the sign-in is keyless (Workload Identity Federation).

**Where to look.** **GitHub:** your repository → **Actions** → the top run: checks, image builds, `infra`, `deploy`, about 20 minutes in all. The slowest part is Firestore's five expiry rules (TTL) and one index, about 7 minutes of the `infra` job.

**Check** on GitHub:
- `infra` job → **Plan**: `Plan: 51 to add, 0 to change, 0 to destroy.` **Apply that plan** ends with `Apply complete!`. After one of the warnings below, its last plan and apply cover only what was left, for example `Plan: 1 to add`.
- `deploy` job → **Check the live URL**: its last line, `Live: https://…`, opens Cloud Ticketing's home page. In the Cloud Shell terminal, `terraform -chdir=infra output -raw web_url` prints the same address.

**Warnings you will likely see.** In a new project, Google is still setting some things up during the first apply (Eventarc was not ready for the first trigger in every dry run). The `infra` job then prints a warning, waits a minute, plans what is left and applies it, by itself (`scripts/infra.sh`):
- `Eventarc was not ready for the trigger yet`, after `Permission denied while using the Eventarc Service Agent`
- `Firestore's new database was made but not readable yet`, after `Root object was present, but now absent`: the job imports the database into the state first

**If stuck.** If the `infra` job still fails (for example on `SERVICE_DISABLED` while permissions spread): **GitHub:** that run → **Re-run jobs** → **Re-run failed jobs**. It creates only what is missing, then deploys.

**Why.** The app is applied by GitHub Actions from the very first time, from the code and settings you just pushed. Its plan and apply run as `tickets-terraform`, with the roles you read in step 2. Its state is in the same bucket, so Cloud Shell sees what GitHub Actions built.

## Step 5. Measure the cold start (Cloud Shell terminal: 1 minute after a 15-minute wait)

**Problem.** With no requests, Cloud Run scales to zero instances. Idle time costs nothing, but the next visitor waits while a new instance starts.

**While you wait** (Cloud Shell Editor): **Open Editor** → `infra/run.tf`. Find the web service (`resource "google_cloud_run_v2_service" "svc"`), the `min_instance_count` line, and `ignore_changes` in its `lifecycle` block. Step 6 explains why that minimum is ignored.

**Do** in the Cloud Shell terminal. Close the site's tab, send no requests for at least 15 minutes, then:

```bash
URL=$(terraform -chdir=infra output -raw web_url)
for i in 1 2 3; do curl -s -o /dev/null -w '%{time_total}s  %header{x-served-by}\n' "$URL/health"; done
```

**Expect.** The first request takes about 4–6 seconds, the next ones about 0.1 seconds (the pre-check measured 4.6 s and 0.07 s). The end of each line names the service, revision and instance that answered; all three lines show the same instance.

**Where to look.** **Console:** ☰ → **Cloud Run** → `web` → **Logs**: `Starting new instance. Reason: AUTOSCALING`, the record of the first request starting an instance.

**Why.** Cloud Run keeps an idle instance for up to 15 minutes. The deploy in step 4 calls the new revision to test it, so right after a deploy an instance is still there.

## Step 6. One minimum instance, through a pull request (Cloud Shell Editor and terminal, then GitHub: 10 minutes)

**Problem.** When an event's signup opens, the first visitors wait 4–6 seconds.

**Do.**
1. **Cloud Shell terminal:** start a branch from an up-to-date main.

   ```bash
   git switch main && git pull
   git switch -c min-instances-1
   ```

2. **Cloud Shell Editor:** **Open Editor** → in the file list, `gdgoc-tickets-iac/infra/terraform.tfvars`. Change the last line to `web_min_instances = 1` and save (Ctrl+S, or Cmd+S on a Mac).
3. **Cloud Shell terminal:** check the change and preview it. A local plan changes nothing.

   ```bash
   git diff
   terraform -chdir=infra plan
   ```

   `git diff` shows one line going from `0` to `1`; the plan ends with `Plan: 0 to add, 1 to change, 0 to destroy.`
4. **Cloud Shell terminal:** commit, push, and open the pull request. The last line printed is the pull request's address.

   ```bash
   git commit -am "web: keep one instance warm"
   git push -u origin min-instances-1
   gh pr create --fill
   ```

5. **GitHub:** open that address. Within 1–2 minutes, GitHub Actions posts the plan as a comment; compare it with the expectation below. Then **Merge pull request** → **Confirm merge**. Once it is on main, GitHub Actions plans again, runs the destroy check, and applies (about 3 minutes).
6. **Cloud Shell terminal:** back to main, up to date.

   ```bash
   git switch main && git pull
   ```

**Expect.** The pull request's **Terraform plan** comment:

```
  # google_cloud_run_v2_job.housekeeping[0] will be updated in-place
  ~ resource "google_cloud_run_v2_job" "housekeeping" {
        …
                  - env {
                      - name  = "WEB_MIN_INSTANCES" -> null
                      - value = "0" -> null
                    }
                  + env {
                      + name  = "WEB_MIN_INSTANCES"
                      + value = "1"
                    }
        …
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Above it: `This plan destroys nothing. Merging to main plans it again and applies it.` Environment variables are an unordered set, so one changed value shows as that entry removed (`-`) and added again (`+`).

**Where to look.** **GitHub:** the pull request's comment, and `pr-plan` on its **Checks** tab. After the merge: **Actions** → the top run → the `infra` job. `build` and `deploy` are skipped, because only `infra/` changed.

**If stuck.**
- `git diff` prints nothing: the file is not saved. Save it in the Editor and run `git diff` again.
- `git push` asks for a password: run `gh auth setup-git`, then push again.

**Why.** In real teams, infrastructure code is edited in an editor on a branch, checked as a diff, previewed with a plan, and reaches main only through a pull request whose plan a person reads before merging. The pull request's plan comes from a read-only account (`tickets-terraform-plan`) that takes no state lock; only after the merge to main does the account that can write (`tickets-terraform`) apply, and even that account cannot change who may do what (the foundation you applied in step 3). Pull requests sign in through their own login (the `github-pr` pool), which cannot reach the apply or deploy accounts.

What changes is not the web service but a setting of the `housekeeping` job. The job runs every 5 minutes: from 15 minutes before a signup opening it keeps web at 3 minimum instances, and otherwise at `web_min_instances`. Terraform hands the job the base value and leaves web's minimum to the job (`ignore_changes` in `run.tf`), because two owners of one value would overwrite each other.

## Step 7. Check (Console, Cloud Shell terminal: 2 minutes after a 15-minute wait)

**Do.**
1. The job applies the value within 5 minutes. To apply it now, **Console:** ☰ → **Cloud Run → Jobs** → `housekeeping` → **Execute**.
2. Send no requests for at least 15 minutes, then run step 5's commands again in the **Cloud Shell terminal**.

**Expect.** Now the first request also takes about 0.1 seconds (the pre-check measured 0.12 s). All three lines show the same instance.

**Where to look.**
- **Console:** ☰ → **Cloud Run** → `web` → **YAML**: `run.googleapis.com/minScale: '1'` under the top `metadata`. The `autoscaling.knative.dev/minScale: '0'` under `template` is the revision's own value; the job changes the service's.
- **Console:** `web` → **Observability** → **Metrics** → Container instance count: one idle instance even with no requests.

## Step 8. A change made in the Console: drift (Console, Cloud Shell terminal: 5 minutes)

**Problem.** A popular event opens tonight, and the on-call engineer expects a bigger rush than usual. They raise pre-warm from 3 to 6 instances, directly in the Console. It works for tonight. But the code still says 3, and nothing in git records the change.

**Do.**
1. **Console:** ☰ → **Cloud Run → Jobs** → `housekeeping` → **Edit** → the container's **Variables & Secrets** → set `PREWARM_INSTANCES` to `6` → **Update**.
2. **Cloud Shell terminal:** in your repository's folder:

   ```bash
   terraform -chdir=infra plan
   ```

**Expect.** Terraform finds a change it did not make, and plans to undo it:

```
  # google_cloud_run_v2_job.housekeeping[0] will be updated in-place
  ~ resource "google_cloud_run_v2_job" "housekeeping" {
        …
                  - env {
                      - name  = "PREWARM_INSTANCES" -> null
                      - value = "6" -> null
                    }
                  + env {
                      + name  = "PREWARM_INSTANCES"
                      + value = "3"
                    }
        …
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**Why.** The real cloud no longer matches the code. That gap is drift (드리프트). Every plan compares the two, and the code wins: the next apply sets pre-warm back to 3, so the next big event gets 3 warm instances and nobody knows why. The Console edit was a reasonable fix for tonight, but a fix that should stay belongs in the code.

## Step 9. Undo, with the drift in the plan (GitHub: 5 minutes)

**Problem.** A minimum instance is billed even while idle, so you undo step 6.

**Do** on GitHub:
1. At the bottom of step 6's merged pull request: **Revert** → **Create pull request**.
2. Read the plan in the comment (below), then **Merge pull request** → **Confirm merge**.
3. **Cloud Shell terminal:** `git pull`.

From the Cloud Shell terminal instead: on a new branch, set `web_min_instances = 0`, commit, push, then `gh pr create --fill`.

**Expect.** The comment's plan changes the housekeeping job in two places: the change you are undoing, `WEB_MIN_INSTANCES` from `"1"` to `"0"`, and one that nobody made in git, `PREWARM_INSTANCES` from `"6"` to `"3"`. Both are in one job, so the plan still reads `Plan: 0 to add, 1 to change, 0 to destroy.`

**Decide.** This is how drift is usually found: in the plan of an unrelated change.
- The 6 was for tonight only: merge. Git wins, and pre-warm is 3 again.
- The 6 should stay: put it in the code first. In this pull request, add `prewarm = { instances = 6, minutes_before = 15, minutes_after = 60 }` to `infra/terraform.tfvars`; the plan comment then changes only `WEB_MIN_INSTANCES`.

For this lab, merge.

**Check.** After the run, **Console:** `housekeeping` → **Edit** → **Variables & Secrets** shows `PREWARM_INSTANCES` `3` and `WEB_MIN_INSTANCES` `0`. `git log --oneline` keeps both the change and its undo.

**Why.** Changing values back in the Console would leave no record in git. The undo is a pull request too, and goes through the same steps: plan review, merge, the destroy check, apply. Because CI applies the whole code every time, a hand change cannot quietly stay: it goes into git, or the next apply removes it.

## Step 10. Clean up (GitHub, Cloud Shell terminal: 10 minutes)

1. **GitHub:** in the **Actions** tab, check that step 9's undo has finished. Destroying while a run is going fails on the state lock.
2. **GitHub:** your repository → **Settings → Secrets and variables → Actions → Variables**: delete `DEPLOY_ENABLED` (or in the Cloud Shell terminal: `gh variable delete DEPLOY_ENABLED`), so no later push deploys to a deleted project.
3. **Cloud Shell terminal:** the app first, then the foundation it runs as.

   ```bash
   terraform -chdir=infra destroy
   terraform -chdir=infra/bootstrap destroy
   ```

   Read `Plan: 0 to add, 0 to change, 51 to destroy.` and type `yes` (about 7 minutes), then `55 to destroy` and `yes` (about 2 minutes).

The state bucket `PROJECT_ID-tfstate` stays, because it was made outside Terraform. To delete it, **Console:** ☰ → **Cloud Storage → Buckets**.
