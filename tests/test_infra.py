"""Terraform in CI (scripts/infra.sh), against a pretend terraform and gh.

The script runs from a copy in a temporary repository, because it writes
terraform.tfvars next to itself and the real one must stay untouched.
"""

import json
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent

FAKE_TERRAFORM = r"""
import os, sys

with open(os.environ["CALLS"], "a") as calls:
    calls.write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1] == "show":
    print(os.environ["PLAN_JSON"] if "-json" in sys.argv else os.environ["PLAN_TEXT"])
# APPLY_ERRORS: what the first applies print as they fail, separated by |; later applies succeed
if sys.argv[1] == "apply" and os.environ.get("APPLY_ERRORS"):
    errors, count = os.environ["APPLY_ERRORS"].split("|"), os.environ["CALLS"] + ".applies"
    done = int(open(count).read()) if os.path.exists(count) else 0
    open(count, "w").write(str(done + 1))
    if done < len(errors):
        print(errors[done])
        sys.exit(1)
sys.exit(1 if os.environ.get("FAIL_ON") == sys.argv[1] else 0)
"""

# Successful runs on main, newest first, as RUNS: [{"id", "sha", "jobs": names that succeeded}]
FAKE_GH = r"""
import json, os, re, sys

if os.environ.get("GH_FAILS"):
    sys.exit(1)
runs, args = json.loads(os.environ["RUNS"]), sys.argv[1:]
if args[:2] == ["run", "list"]:
    for run in runs:
        print(run["id"], run["sha"])
elif args[:2] == ["run", "view"]:
    wanted = re.search(r'\.name == "([\w-]+)"', " ".join(args))[1]
    run = next(run for run in runs if str(run["id"]) == args[2])
    if args[-1].endswith("| .conclusion"):  # which way the job ended: "failed" lists the jobs that failed
        if wanted in run.get("failed", []):
            print("failure")
        elif wanted in run["jobs"]:
            print("success")
    elif wanted in run["jobs"]:
        print(wanted)
elif args[0] == "api" and "-X" not in args:
    # the pull request's comments; COMMENTS: [{"id", "body"}]
    for comment in json.loads(os.environ.get("COMMENTS", "[]")):
        if comment["body"].startswith("<!-- terraform-plan -->"):
            print(comment["id"])
elif args[0] == "api":
    method = args[args.index("-X") + 1]
    body = open(next(a for a in args if a.startswith("body=@"))[len("body=@"):]).read()
    with open(os.environ["GH_CALLS"], "a") as calls:
        calls.write(json.dumps({"method": method, "path": args[args.index(method) + 1], "body": body}) + "\n")
"""


def plan_json(*actions):
    return json.dumps(
        {"resource_changes": [{"address": f"thing.{i}", "change": {"actions": a}} for i, a in enumerate(actions)]}
    )


class Repo:
    def __init__(self, path):
        self.path = path
        (path / "scripts").mkdir()
        (path / "infra").mkdir()
        (path / "bin").mkdir()
        shutil.copy(REPO / "scripts/infra.sh", path / "scripts/infra.sh")
        (path / "infra/run.tf").write_text("first\n")
        (path / "app.py").write_text("first\n")
        for name, source in (("terraform", FAKE_TERRAFORM), ("gh", FAKE_GH), ("sleep", "")):
            tool = path / "bin" / name
            tool.write_text(f"#!{sys.executable}\n{source}")
            tool.chmod(tool.stat().st_mode | stat.S_IEXEC)
        self.git("init", "-q")
        self.first = self.commit("first")

    def git(self, *args):
        identity = ["-c", "user.name=t", "-c", "user.email=t@example.com"]
        done = subprocess.run(["git", *identity, *args], cwd=self.path, check=True, capture_output=True, text=True)
        return done.stdout.strip()

    def commit(self, message):
        self.git("add", "scripts", "infra", "app.py")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def run(self, stage, **env):
        env = {
            "PATH": f"{self.path / 'bin'}{os.pathsep}{os.environ['PATH']}",
            "CALLS": str(self.path / "calls"),
            "GITHUB_OUTPUT": str(self.path / "output"),
            "GITHUB_EVENT_NAME": "push",
            "PROJECT_ID": "my-project",
            "TFVARS": 'project_id = "my-project"',
            "RUNS": json.dumps([{"id": 1, "sha": self.first, "jobs": ["infra", "deploy"]}]),
            "PLAN_TEXT": "Plan: 0 to add, 1 to change, 0 to destroy.",
            "GH_CALLS": str(self.path / "gh_calls"),
            "GITHUB_REPOSITORY": "student/gdgoc-tickets-iac",
            "PR_NUMBER": "3",
            "HEAD_SHA": "abcdef1234567",
            "PLAN_JSON": plan_json(),
            **env,
        }
        return subprocess.run(
            ["bash", str(self.path / "scripts/infra.sh"), stage], env=env, capture_output=True, text=True
        )

    def needs(self, **env) -> dict:
        """What scripts/infra.sh changes says this push needs: {"infra": bool, "app": bool}."""
        done = self.run("changes", **env)
        assert done.returncode == 0, done.stderr
        lines = (self.path / "output").read_text().split()
        return {name: value == "true" for name, value in (line.split("=") for line in lines)}

    def applies(self, **env) -> bool:
        return self.needs(**env)["infra"]

    @property
    def calls(self) -> list[str]:
        return (self.path / "calls").read_text().splitlines()

    @property
    def gh_calls(self) -> list[dict]:
        return [json.loads(line) for line in (self.path / "gh_calls").read_text().splitlines()]

    def pull_request(self, path: str):
        """Change one file on a branch, then check out the pull request the way GitHub does:
        the branch merged into its base, which is the merge's first parent."""
        base = self.git("rev-parse", "--abbrev-ref", "HEAD")
        self.git("switch", "-q", "-c", "change")
        (self.path / path).write_text("second\n")
        self.commit("the change")
        self.git("switch", "-q", base)
        self.git(
            "-c", "user.name=t", "-c", "user.email=t@example.com", "merge", "-q", "--no-ff", "change", "-m", "merge"
        )


@pytest.fixture
def repo(tmp_path):
    return Repo(tmp_path)


def test_a_push_that_leaves_infra_alone_applies_nothing(repo):
    (repo.path / "app.py").write_text("second\n")
    repo.commit("code only")
    assert repo.needs() == {"infra": False, "app": True}


def test_a_push_that_changes_only_infra_applies_without_a_build_or_deploy(repo):
    (repo.path / "infra/run.tf").write_text("second\n")
    repo.commit("settings")
    assert repo.needs() == {"infra": True, "app": False}


def test_a_run_from_before_deploys_were_on_is_not_a_deploy(repo):
    (repo.path / "infra/run.tf").write_text("second\n")
    second = repo.commit("settings, pushed before the repository was connected")
    runs = [{"id": 2, "sha": second, "jobs": []}, {"id": 1, "sha": repo.first, "jobs": []}]
    assert repo.needs(RUNS=json.dumps(runs)) == {"infra": True, "app": True}


def test_the_app_compares_with_the_last_deploy_not_the_last_apply(repo):
    (repo.path / "app.py").write_text("second\n")
    second = repo.commit("code: its deploy failed, so the run failed and is not listed")
    (repo.path / "infra/run.tf").write_text("second\n")
    third = repo.commit("settings: applied, no deploy")
    runs = [{"id": 3, "sha": third, "jobs": ["infra"]}, {"id": 1, "sha": repo.first, "jobs": ["infra", "deploy"]}]
    assert second  # between the last deploy and now
    assert repo.needs(RUNS=json.dumps(runs)) == {"infra": False, "app": True}


def test_a_failed_apply_is_tried_again_by_the_next_push(repo):
    (repo.path / "infra/run.tf").write_text("second\n")
    repo.commit("settings: its run failed, so it is not the last success")
    (repo.path / "app.py").write_text("second\n")
    repo.commit("code only")
    assert repo.applies()


def test_after_a_failed_apply_a_revert_to_the_last_success_applies_again(repo):
    # The failed apply changed the cloud (a revision nobody wanted), and the revert's files match the
    # last success exactly, so comparing files alone would skip the repair
    runs = [
        {"id": 2, "sha": repo.first, "jobs": [], "failed": ["infra"]},
        {"id": 1, "sha": repo.first, "jobs": ["infra", "deploy"]},
    ]
    assert repo.applies(RUNS=json.dumps(runs))


def test_once_an_apply_succeeds_again_unchanged_files_apply_nothing(repo):
    runs = [
        {"id": 3, "sha": repo.first, "jobs": ["infra"]},
        {"id": 2, "sha": repo.first, "jobs": [], "failed": ["infra"]},
    ]
    assert not repo.applies(RUNS=json.dumps(runs))


def test_a_run_started_by_a_person_always_applies_and_deploys(repo):
    assert repo.needs(GITHUB_EVENT_NAME="workflow_dispatch") == {"infra": True, "app": True}


@pytest.mark.parametrize(
    "runs",
    [[], [{"id": 1, "sha": "0" * 40, "jobs": ["infra", "deploy"]}]],
    ids=["no successful run yet", "a commit that is gone"],
)
def test_applies_and_deploys_when_there_is_nothing_to_compare_with(repo, runs):
    assert repo.needs(RUNS=json.dumps(runs)) == {"infra": True, "app": True}


@pytest.mark.parametrize(("path", "plans"), [("infra/run.tf", True), ("app.py", False)], ids=["infra", "app only"])
def test_a_pull_request_is_planned_only_when_it_changes_infra(repo, path, plans):
    repo.pull_request(path)
    assert repo.needs(GITHUB_EVENT_NAME="pull_request") == {"infra": plans, "app": True}


def test_a_failed_lookup_stops_the_job_instead_of_guessing(repo):
    assert repo.run("changes", GH_FAILS="1").returncode != 0


def test_plan_uses_the_shared_state_and_the_settings_from_github(repo):
    assert repo.run("plan").returncode == 0
    assert (repo.path / "infra/terraform.tfvars").read_text() == 'project_id = "my-project"\n'
    assert "bucket=my-project-tfstate" in repo.calls[0]
    assert "prefix=gdgoc-tickets" in repo.calls[0]
    assert "-out=tfplan" in repo.calls[1]


def test_a_pull_requests_plan_takes_no_lock_and_keeps_the_text(repo):
    assert repo.run("pr-plan").returncode == 0
    assert "-lock=false" in repo.calls[1] and "-out=tfplan" in repo.calls[1]
    assert repo.calls[2] == "show -no-color tfplan"
    assert (repo.path / "infra/plan.txt").read_text().strip() == "Plan: 0 to add, 1 to change, 0 to destroy."


def test_the_plan_is_posted_once_then_updated_in_place(repo):
    assert repo.run("pr-plan").returncode == 0
    assert repo.run("comment").returncode == 0
    old = {"id": 7, "body": "<!-- terraform-plan -->\nan older plan"}
    assert repo.run("comment", COMMENTS=json.dumps([{"id": 5, "body": "LGTM"}, old])).returncode == 0
    first, second = repo.gh_calls
    assert (first["method"], first["path"]) == ("POST", "repos/student/gdgoc-tickets-iac/issues/3/comments")
    assert (second["method"], second["path"]) == ("PATCH", "repos/student/gdgoc-tickets-iac/issues/comments/7")
    assert first["body"].startswith("<!-- terraform-plan -->\n### Terraform plan for abcdef1")
    assert "Plan: 0 to add, 1 to change, 0 to destroy." in first["body"]
    assert "destroys nothing" in first["body"]


def test_the_comment_names_what_a_plan_would_destroy(repo):
    doomed = plan_json(["update"], ["delete", "create"])
    assert repo.run("pr-plan").returncode == 0
    assert repo.run("comment", PLAN_JSON=doomed).returncode == 0
    body = repo.gh_calls[0]["body"]
    assert "destroys or replaces" in body and "thing.1" in body and "thing.0" not in body.split("```")[1]


def test_plan_prefers_the_settings_committed_to_the_repository(repo):
    (repo.path / "infra/terraform.tfvars").write_text('project_id = "my-project"\nweb_min_instances = 1\n')
    assert repo.run("plan").returncode == 0
    assert "web_min_instances = 1" in (repo.path / "infra/terraform.tfvars").read_text()


def test_plan_without_any_settings_stops(repo):
    done = repo.run("plan", TFVARS="")
    assert done.returncode != 0
    assert "terraform.tfvars" in done.stdout
    assert not (repo.path / "calls").exists()


@pytest.mark.parametrize("actions", [(), (["no-op"], ["create"], ["update"])], ids=["no changes", "adds and updates"])
def test_a_plan_that_destroys_nothing_passes(repo, actions):
    assert repo.run("check", PLAN_JSON=plan_json(*actions)).returncode == 0


@pytest.mark.parametrize(
    "doomed", [["delete"], ["delete", "create"], ["create", "delete"]], ids=["delete", "replace", "replace, new first"]
)
def test_a_plan_that_destroys_anything_stops_and_names_it(repo, doomed):
    done = repo.run("check", PLAN_JSON=plan_json(["create"], doomed))
    assert done.returncode != 0
    assert "thing.1" in done.stdout
    assert "thing.0" not in done.stdout


def test_a_person_can_allow_a_destroy_and_it_is_still_named(repo):
    done = repo.run("check", PLAN_JSON=plan_json(["create"], ["delete"]), ALLOW_DESTROY="true")
    assert done.returncode == 0
    assert "thing.1" in done.stdout
    assert repo.run("check", PLAN_JSON=plan_json(["delete"]), ALLOW_DESTROY="").returncode != 0  # a push


def test_a_plan_that_cannot_be_read_stops(repo):
    assert repo.run("check", FAIL_ON="show").returncode != 0


def test_apply_applies_the_saved_plan_and_reports_failure(repo):
    assert repo.run("apply").returncode == 0
    assert repo.calls == ["apply -input=false -no-color tfplan"]
    assert repo.run("apply", FAIL_ON="apply").returncode != 0


EVENTARC_NOT_READY = "Error: Error creating Trigger: Permission denied while using the Eventarc Service Agent."


def test_apply_plans_the_rest_and_tries_once_more_when_eventarc_is_not_ready(repo):
    done = repo.run("apply", APPLY_ERRORS=EVENTARC_NOT_READY)
    assert done.returncode == 0, done.stdout + done.stderr
    applies = [i for i, call in enumerate(repo.calls) if call.startswith("apply")]
    assert len(applies) == 2
    between = repo.calls[applies[0] + 1 : applies[1]]
    assert any(call.startswith("plan ") for call in between) and "show -json tfplan" in between


def test_apply_does_not_try_again_after_any_other_error(repo):
    assert repo.run("apply", APPLY_ERRORS="Error: Error creating Topic: quota exceeded").returncode != 0
    assert [call for call in repo.calls if call.startswith("apply")] == ["apply -input=false -no-color tfplan"]


def test_apply_gives_up_after_two_more_tries(repo):
    done = repo.run("apply", APPLY_ERRORS="|".join([EVENTARC_NOT_READY] * 3))
    assert done.returncode != 0
    assert len([call for call in repo.calls if call.startswith("apply")]) == 3


def test_a_dropped_database_then_eventarc_both_heal(repo):
    done = repo.run("apply", APPLY_ERRORS=f"{DATABASE_DROPPED}|{EVENTARC_NOT_READY}")
    assert done.returncode == 0, done.stdout + done.stderr
    assert len([call for call in repo.calls if call.startswith("apply")]) == 3
    assert len([call for call in repo.calls if call.startswith("import")]) == 1


DATABASE_DROPPED = """Error: Provider produced inconsistent result after apply

When applying changes to google_firestore_database.main[0], provider
"provider[\\"registry.terraform.io/hashicorp/google\\"]" produced an unexpected
new value: Root object was present, but now absent."""


@pytest.mark.parametrize(
    "error",
    [DATABASE_DROPPED, "Error: Error creating Database: googleapi: Error 409: Database already exists."],
    ids=["dropped from the state", "already exists"],
)
def test_a_database_made_but_not_recorded_is_imported_before_the_second_try(repo, error):
    done = repo.run("apply", APPLY_ERRORS=error)
    assert done.returncode == 0, done.stdout + done.stderr
    imports = [call for call in repo.calls if call.startswith("import")]
    assert imports == [
        "import -input=false -no-color google_firestore_database.main[0] projects/my-project/databases/(default)"
    ]
    assert repo.calls.index(imports[0]) < max(i for i, call in enumerate(repo.calls) if call.startswith("apply"))


def test_the_eventarc_retry_imports_nothing(repo):
    assert repo.run("apply", APPLY_ERRORS=EVENTARC_NOT_READY).returncode == 0
    assert not [call for call in repo.calls if call.startswith("import")]


def test_a_second_try_that_would_destroy_anything_stops(repo):
    done = repo.run("apply", APPLY_ERRORS=EVENTARC_NOT_READY, PLAN_JSON=plan_json(["delete", "create"]))
    assert done.returncode != 0
    assert len([call for call in repo.calls if call.startswith("apply")]) == 1


def workflow_job(name: str) -> str:
    workflow = (REPO / ".github/workflows/ci.yml").read_text()
    return re.search(rf"^  {name}:\n.*?(?=^  \w[\w-]*:\n|\Z)", workflow, re.M | re.S).group()


def test_the_workflow_applies_before_the_deploy_and_a_failure_stops_the_deploy():
    infra, deploy = workflow_job("infra"), workflow_job("deploy")
    assert re.findall(r"run: scripts/infra\.sh (\w+)", workflow_job("changes")) == ["changes"]
    assert re.findall(r"run: scripts/infra\.sh (\w+)", infra) == ["plan", "check", "apply"]
    assert "needs: [build, infra]" in deploy
    assert "needs.infra.result != 'failure'" in deploy


def test_a_push_that_changes_only_infra_skips_the_build_but_not_the_checks():
    build, infra = workflow_job("build"), workflow_job("infra")
    assert "if: needs.changes.outputs.app == 'true'" in build
    assert "needs.changes.outputs.infra == 'true'" in infra
    # A skipped build must not let infra through when a check failed
    for check in ("lint", "test", "emulator", "audit", "image-scan", "dockerfile", "terraform"):
        assert re.search(rf"needs: \[[^\]]*\b{check}\b", infra), check
    assert "!contains(needs.*.result, 'failure')" in infra


def test_pull_requests_plan_with_their_own_read_only_login():
    job = workflow_job("pr-plan")
    assert "github.event_name == 'pull_request'" in job
    assert "needs.changes.outputs.infra == 'true'" in job
    assert "github.event.pull_request.head.repo.full_name == github.repository" in job  # no forks
    assert "workload_identity_provider: ${{ vars.WIF_PR_PROVIDER }}" in job
    assert "service_account: ${{ vars.TERRAFORM_PLAN_SA }}" in job
    assert "pull-requests: write" in job
    assert re.findall(r"run: scripts/infra\.sh ([\w-]+)", job) == ["pr-plan", "comment"]
    assert "vars.TERRAFORM_SA" not in job and "vars.DEPLOYER_SA" not in job


def test_only_the_infra_job_uses_the_terraform_login():
    workflow = (REPO / ".github/workflows/ci.yml").read_text()
    assert workflow.count("service_account: ${{ vars.TERRAFORM_SA }}") == 1
    assert "service_account: ${{ vars.TERRAFORM_SA }}" in workflow_job("infra")
    assert "vars.DEPLOYER_SA" not in workflow_job("infra")


def test_the_image_scan_stops_a_deploy_only_with_production_extras():
    scan = workflow_job("image-scan")
    assert "exit-code: ${{ vars.PRODUCTION_EXTRAS == 'true' && '1' || '0' }}" in scan
    assert (
        "PRODUCTION_EXTRAS = tostring(var.production_extras)"
        in (REPO / "infra/modules/foundation/outputs.tf").read_text()
    )
