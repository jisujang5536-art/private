# Terraform과 GitOps 실습

8회차의 Cloud Ticketing 전체를 이번에는 Terraform이 새 프로젝트에 만듭니다. 앱 코드와 Terraform 코드는 완성되어 있고, 이 실습에서는 Terraform의 작업 흐름을 익힙니다. 실행 계획을 읽고, 적용하고, 설정 한 줄을 바꿔 실제 동작이 달라지는 것을 측정합니다.

코드는 두 부분으로 나뉘고, 적용하는 계정도 다릅니다. 기반(API, 모든 서비스 계정과 역할, GitHub의 키 없는 로그인)은 누가 무엇을 할 수 있는지를 정하므로 Cloud Shell에서 직접 plan하고 apply합니다. 앱(서비스, 데이터베이스, 토픽, 잡)은 GitHub Actions가 적용하며, 이 계정은 권한을 바꿀 수 없습니다. 앱의 모든 변경은 pull request로 올립니다. GitHub Actions가 실행 계획을 pull request에 댓글로 올리고, 그 계획을 읽고 병합하면 GitHub Actions가 apply합니다. 원하는 상태를 git에 두고 도구가 그 상태를 적용하는 방식(GitOps)입니다.

명령만 한 장으로 보려면 [terraform-quickstart.ko.md](terraform-quickstart.ko.md). English: [terraform-lab.en.md](terraform-lab.en.md).

| | |
|---|---|
| 수준 | 입문 (200) |
| 시간 | 약 70분, 콜드 스타트 측정 전 15분 대기 두 번 |
| 비용 | 실습 동안 수백 원. 최소 인스턴스 1은 쉬는 동안에도 과금되므로 9단계에서 0으로 되돌림 |
| 마지막 점검 | 2026-11-23, 새 프로젝트와 그 프로젝트에 연결한 저장소에서 처음부터 끝까지(pull request, 되돌리기 포함) |

**마치면 할 수 있는 것**

- 실행 계획에서 만들어질 것, 바뀔 것, 지워질 것 읽기
- 상태 파일을 Cloud Storage 버킷(원격 백엔드)에 두는 이유 설명
- 기반과 앱을 서로 다른 계정으로 나누어 적용하는 이유 설명
- 설정 변경을 pull request로 올려 실행 계획을 검토하고, 병합으로 적용하기
- 콜드 스타트와 최소 인스턴스를 자신의 측정값으로 비교
- plan에서 드리프트(Terraform 밖에서 생긴 변경)를 알아보고, 코드에 넣을지 git으로 되돌릴지 결정하기

## 전체 흐름

| 단계 | 할 일 | 작업하는 곳 |
|---|---|---|
| 0 | 새 프로젝트, 내 저장소, 로그인 | 콘솔, GitHub, Cloud Shell 터미널 |
| 1 | 설정 파일, 상태 버킷, `terraform init`(`./lab bootstrap`) | Cloud Shell 터미널 |
| 2, 3 | 기반: `infra/bootstrap`에서 `terraform plan`, `terraform apply` | Cloud Shell 터미널 |
| 4 | GitHub Actions 연결, 첫 push로 앱 생성과 배포(`./lab connect`, `git push`) | Cloud Shell 터미널, 이어서 GitHub |
| 5~7 | 콜드 스타트 측정, pull request로 설정 변경, 확인 | Cloud Shell 터미널과 편집기, GitHub, 콘솔 |
| 8 | 콘솔에서 바꾼 설정: 드리프트 | 콘솔, Cloud Shell 터미널 |
| 9, 10 | 되돌리기(**Revert**)와 plan에 나타난 드리프트, 전체 삭제: 앱, 이어서 기반(`terraform destroy`) | GitHub, Cloud Shell 터미널 |

**스크립트는 처음 준비에만 씁니다.** `./lab bootstrap`과 `./lab connect`는 한 번만 하는 준비(상태 버킷, 설정 파일, GitHub Actions 연결)입니다. 실무 팀도 이 부분은 스크립트로 한 번 실행합니다. 그 뒤의 모든 단계는 terraform, git, gcloud, curl, GitHub 같은 표준 도구로 하고, 인프라를 만들고 바꾸는 plan과 apply는 직접 실행하거나 GitHub Actions가 실행합니다.

**각 단계의 구성:** 문제 → 할 일 → 예측 → 어디서 볼까 → 확인 → 이유, 막히면.

## 작업하는 곳

| 곳 | 여는 방법 | 하는 일 |
|---|---|---|
| **콘솔** | console.cloud.google.com, 위쪽에서 실습 프로젝트 선택 | 프로젝트, 결제, 예산 만들기. Cloud Run과 로그, YAML 보기 |
| **Cloud Shell 터미널** | 콘솔 오른쪽 위 **Cloud Shell 활성화**(>_) | 이 안내의 모든 명령. 명령은 내 저장소 폴더 `gdgoc-tickets-iac`에서 시작 |
| **Cloud Shell 편집기** | Cloud Shell 막대의 **편집기 열기** | 인프라 코드 수정(6단계의 `infra/terraform.tfvars`), 기다리는 동안 `infra/run.tf` 같은 코드 읽기 |
| **GitHub**(웹사이트) | 브라우저의 github.com → 내 저장소 | 템플릿 복사, **Actions** 탭, pull request로 하는 변경, **Revert** |

회색 상자의 명령은 모두 **Cloud Shell 터미널**에서 실행합니다(편집기 아래쪽에도 같은 터미널이 있습니다). 파일 수정은 **Cloud Shell 편집기**에서 합니다. **GitHub**는 항상 브라우저의 GitHub 웹사이트이고, pull request 검토, 병합, 되돌리기를 합니다.

---

## 0단계. 프로젝트와 저장소 (콘솔, GitHub, Cloud Shell 터미널: 10분)

**문제.** 8회차 프로젝트에는 손으로 만든 리소스가 남아 있어, Terraform이 같은 이름으로 만들면 충돌합니다. 빈 프로젝트에서 시작합니다.

**할 일.**
1. **콘솔:** ☰ → **IAM 및 관리자 → 리소스 관리** → **프로젝트 만들기**. **프로젝트 ID**를 적어 둡니다.
2. **콘솔:** ☰ → **결제 → 내 프로젝트**에서 새 프로젝트에 결제 계정을 연결합니다. 프로젝트 수 한도로 거부되면 8회차 프로젝트를 **결제 사용 중지**한 뒤 다시 연결합니다.
3. **콘솔:** ☰ → **결제 → 예산 및 알림** → **예산 만들기**. 범위: 새 프로젝트, 금액: 12,000원.
4. **GitHub:** `joyrla/gdgoc-tickets-lab` → **Use this template** → **Create a new repository**. 이름 `gdgoc-tickets-iac`, **Private**.
5. **Cloud Shell 터미널:** 콘솔 오른쪽 위 **Cloud Shell 활성화**(>_)를 누릅니다. 열린 터미널에서 GitHub에 로그인합니다. Enter를 누르고 화면의 코드를 [github.com/login/device](https://github.com/login/device)에 입력합니다.

   ```bash
   gh auth login --hostname github.com --git-protocol https --web --scopes workflow
   ```

6. **Cloud Shell 터미널:** 내 저장소를 받습니다. 비공개 저장소라 로그인 뒤에 받습니다.

   ```bash
   gh repo clone 내_GitHub_ID/gdgoc-tickets-iac
   cd gdgoc-tickets-iac
   ```

**확인.** `ls`에 `lab`, `infra`, `web`이 보입니다.

## 1단계. 설정 파일과 상태 버킷 (Cloud Shell 터미널: 2분)

**문제.** Terraform은 무엇을 어디에 만들지(설정)와 지금까지 무엇을 만들었는지(상태)를 알아야 합니다. 상태가 Cloud Shell에만 있으면 GitHub Actions는 볼 수 없습니다.

**할 일.** Cloud Shell 터미널의 `gdgoc-tickets-iac` 폴더에서:

```bash
./lab bootstrap 프로젝트_ID
source ~/.bashrc
```

**이 명령이 하는 일.**
0. Terraform 1.9.8 설치(`~/bin`). Cloud Shell에는 2026년 6월부터 Terraform이 기본으로 들어 있지 않습니다. `source ~/.bashrc`는 지금 열린 터미널이 `~/bin`의 Terraform을 찾게 합니다.
1. 설정 파일 두 개 작성. 기반의 `infra/bootstrap/terraform.tfvars`: 프로젝트 ID, 저장소 번호. 앱의 `infra/terraform.tfvars`: 같은 두 값, 관리자 이메일, `terraform_in_ci = true`, `layer = "app"`, `web_min_instances = 0`
2. 상태 버킷 `프로젝트_ID-tfstate` 생성: 객체 버전 관리, 공개 액세스 방지. 기반과 앱의 상태는 이 버킷 안에 따로 저장(`gdgoc-tickets-bootstrap`, `gdgoc-tickets`)
3. 두 폴더에서 `terraform init`: 프로바이더 설치, 각 상태 위치를 버킷으로 지정
4. Eventarc 서비스 에이전트 생성: 4단계에서 트리거를 만들 수 있게 미리 준비

**확인.** 마지막 줄 `Then, back in the top folder (cd ../..): ./lab connect`. `terraform version`이 `Terraform v1.9.8`. `cat infra/bootstrap/terraform.tfvars infra/terraform.tfvars`로 두 설정 파일을 읽어 봅니다(Cloud Shell 편집기로 열어도 됩니다).

**막히면.** `./lab bootstrap`이 `infra/terraform.tfvars links to ~/.gdgoc-lab`으로 멈추면, 8회차용 `./lab` 명령을 먼저 실행한 경우입니다. 화면의 `rm` 명령을 실행하고 다시 bootstrap합니다.

**이유.** 상태 파일에는 만든 리소스 목록과 생성된 비밀 값이 들어 있습니다. 버킷에 두면 Cloud Shell과 GitHub Actions가 같은 상태를 읽고, 한 번에 한 곳만 적용하도록 잠기고(상태 잠금), 이전 버전이 남습니다.

## 2단계. 기반의 실행 계획 (Cloud Shell 터미널: 5분)

**문제.** 적용하기 전에 무엇이 만들어지는지 알아야 합니다. 먼저 누가 무엇을 할 수 있는지를 정하는 기반부터 봅니다.

**할 일.** Cloud Shell 터미널에서:

```bash
cd infra/bootstrap
terraform plan
```

**예측.** 맨 아래 `Plan: 55 to add, 0 to change, 0 to destroy.`

**어디서 볼까.** 터미널의 출력을 위로 올려 다음을 찾습니다.

| 찾을 것 | 읽을 것 |
|---|---|
| `module.foundation.google_service_account.sa["web"]` | 작업마다 하나씩인 서비스 계정. web은 `tickets-web`으로 실행 |
| `module.foundation.google_iam_workload_identity_pool_provider.github[0]` | `attribute_condition`에 내 저장소 번호, `refs/heads/main`, 로그인할 수 있는 두 이벤트 |
| `module.foundation.google_project_iam_member.terraform["roles/run.admin"]` | GitHub Actions가 앱을 적용하는 계정 `tickets-terraform`의 프로젝트 역할 10개 중 하나. 권한을 바꾸는 역할은 없음 |
| `module.foundation.google_artifact_registry_repository.images[0]` | 첫 push가 이미지를 올릴 저장소 |

**이유.** plan은 아무것도 바꾸지 않습니다. 코드(원하는 상태), 상태 파일, 실제 클라우드를 비교한 결과입니다.

코드를 둘로 나누는 것은 실무 팀의 방식과 같습니다. 기반은 누가 무엇을 할 수 있는지를 정하고, 기반을 적용하는 쪽은 어떤 권한이든 줄 수 있으므로 사람이 가끔 적용합니다. 앱은 자주 바뀌고, GitHub Actions가 권한을 바꿀 수 없는 역할로 적용합니다. pull request의 실수가 앱을 망가뜨릴 수는 있어도 누구에게 권한을 더 줄 수는 없습니다. 상태도 각각 작게 유지되어(55개, 51개) 상태 하나에 약 100개라는 Google의 권장 기준 아래에 있고, plan이 빠르고 읽기 쉽습니다.

**막히면.** `could not find default credentials`가 나오면 `gcloud auth application-default login`을 실행한 뒤 다시 `terraform plan`.

## 3단계. 기반 적용 (Cloud Shell 터미널: 3분)

**할 일.** Cloud Shell 터미널의 `infra/bootstrap`에서 그대로:

```bash
terraform apply
```

같은 계획이 다시 나오면 `Enter a value:`에 `yes`.

**예측.** `Apply complete! Resources: 55 added, 0 changed, 0 destroyed.` 약 2분.

**확인.**

```bash
terraform output github_variables
```

GitHub Actions가 쓸 값 9개: 프로젝트, 이미지 저장소, 키 없는 로그인 두 개(`WIF_PROVIDER`, `WIF_PR_PROVIDER`), 계정 세 개(`DEPLOYER_SA`, `TERRAFORM_SA`, `TERRAFORM_PLAN_SA`). 비밀 값은 없습니다.

**막히면.** 새 프로젝트에서는 API를 켠 직후 권한이 아직 전파되지 않아 멈출 수 있습니다(`SERVICE_DISABLED`, `Permission denied`). 1~2분 뒤 `terraform apply`를 다시 실행합니다. 이미 만든 것은 건너뛰고 남은 것만 만듭니다.

## 4단계. GitHub Actions 연결, 첫 push로 앱 생성 (Cloud Shell 터미널, 이어서 GitHub: 20분)

**문제.** 이제부터 기준은 Cloud Shell이 아니라 GitHub의 코드입니다. GitHub Actions가 내 프로젝트에 로그인해, 코드대로 앱을 만들고 배포해야 합니다.

**할 일.** Cloud Shell 터미널에서:

```bash
cd ../..
./lab connect
git add infra/terraform.tfvars infra/bootstrap/terraform.tfvars
git commit -m "Terraform settings for my project"
git push
```

`./lab connect`는 기반의 출력값을 저장소 변수(**Settings → Secrets and variables → Actions → Variables**)에 넣고 배포를 켭니다(`DEPLOY_ENABLED`). 비밀 값은 넣지 않습니다. 로그인은 키 없이(Workload Identity Federation) 합니다.

**어디서 볼까.** **GitHub:** 내 저장소 → **Actions** → 맨 위 실행. 검사, 이미지 빌드, `infra`, `deploy` 순서로 약 20분입니다. 가장 오래 걸리는 것은 `infra` 작업 안의 Firestore 만료 규칙(TTL) 5개와 색인 1개입니다(약 7분).

**확인.** GitHub에서:
- `infra` 작업 → **Plan**: `Plan: 51 to add, 0 to change, 0 to destroy.` **Apply that plan**은 `Apply complete!`로 끝납니다. 아래 경고가 나왔다면 마지막 plan과 apply는 남은 것만 다룹니다(예: `Plan: 1 to add`).
- `deploy` 작업 → **Check the live URL**의 마지막 줄 `Live: https://…`를 열면 Cloud Ticketing 첫 화면. Cloud Shell 터미널의 `terraform -chdir=infra output -raw web_url`도 같은 주소입니다.

**나올 가능성이 높은 경고.** 새 프로젝트에서는 첫 apply 동안 Google 쪽 준비가 아직 끝나지 않은 것이 있습니다(사전 점검마다 Eventarc가 첫 트리거를 만들 준비가 안 되어 있었음). 그러면 `infra` 작업이 경고를 남기고 1분 기다린 뒤, 남은 것을 다시 plan해 적용합니다(`scripts/infra.sh`).
- `Permission denied while using the Eventarc Service Agent` 뒤의 `Eventarc was not ready for the trigger yet`
- `Root object was present, but now absent` 뒤의 `Firestore's new database was made but not readable yet`: 이미 만들어진 데이터베이스를 먼저 상태에 가져옴(import)

**막히면.** 그래도 `infra` 작업이 실패하면(예: 권한 전파 중의 `SERVICE_DISABLED`): **GitHub:** 그 실행 → **Re-run jobs** → **Re-run failed jobs**. 남은 것만 만들고 이어서 배포합니다.

**이유.** 앱은 처음부터 GitHub Actions가, 방금 push한 코드와 설정으로 적용합니다. plan과 apply는 2단계에서 읽은 역할을 가진 `tickets-terraform`으로 실행됩니다. 상태는 같은 버킷에 있으므로 Cloud Shell에서도 GitHub Actions가 만든 것을 볼 수 있습니다.

## 5단계. 콜드 스타트 측정 (Cloud Shell 터미널: 15분 대기 후 1분)

**문제.** 요청이 없으면 Cloud Run은 인스턴스를 0개로 줄입니다. 쉬는 동안 비용은 0이지만, 다음 첫 방문자는 새 인스턴스가 시작될 때까지 기다립니다.

**기다리는 동안**(Cloud Shell 편집기): **편집기 열기** → `infra/run.tf`. web 서비스(`resource "google_cloud_run_v2_service" "svc"`), `min_instance_count` 줄, `lifecycle` 블록의 `ignore_changes`를 찾습니다. 이 최소 인스턴스 값을 왜 무시하는지는 6단계에서 설명합니다.

**할 일.** 사이트 탭을 닫고 15분 이상 요청을 보내지 않은 뒤, Cloud Shell 터미널에서:

```bash
URL=$(terraform -chdir=infra output -raw web_url)
for i in 1 2 3; do curl -s -o /dev/null -w '%{time_total}s  %header{x-served-by}\n' "$URL/health"; done
```

**예측.** 첫 요청 약 4~6초, 둘째부터 약 0.1초(사전 점검에서는 4.6초, 0.07초). 줄 끝은 응답한 서비스, 리비전, 인스턴스이고 세 줄이 같은 인스턴스입니다.

**어디서 볼까.** **콘솔:** ☰ → **Cloud Run** → `web` → **로그**: `Starting new instance. Reason: AUTOSCALING`. 첫 요청이 새 인스턴스를 시작시킨 기록입니다.

**이유.** Cloud Run은 쉬는 인스턴스를 최대 15분 남겨 둡니다. 4단계의 배포는 새 리비전을 시험 호출하므로 배포 직후에는 인스턴스가 남아 있습니다.

## 6단계. 최소 인스턴스 1: pull request (Cloud Shell 편집기와 터미널, 이어서 GitHub: 10분)

**문제.** 행사 신청이 열리는 순간 첫 방문자들이 4~6초를 기다립니다.

**할 일.**
1. **Cloud Shell 터미널:** 최신 main에서 새 브랜치를 만듭니다.

   ```bash
   git switch main && git pull
   git switch -c min-instances-1
   ```

2. **Cloud Shell 편집기:** **편집기 열기** → 파일 목록의 `gdgoc-tickets-iac/infra/terraform.tfvars`. 마지막 줄을 `web_min_instances = 1`로 바꾸고 저장합니다(Ctrl+S, Mac은 Cmd+S).
3. **Cloud Shell 터미널:** 변경을 확인하고 미리 봅니다. 로컬 plan은 아무것도 바꾸지 않습니다.

   ```bash
   git diff
   terraform -chdir=infra plan
   ```

   `git diff`에 한 줄이 `0`에서 `1`로 바뀐 것이 보이고, plan은 `Plan: 0 to add, 1 to change, 0 to destroy.`로 끝납니다.
4. **Cloud Shell 터미널:** 커밋하고 push한 뒤 pull request를 엽니다. 마지막 줄에 pull request 주소가 나옵니다.

   ```bash
   git commit -am "web: keep one instance warm"
   git push -u origin min-instances-1
   gh pr create --fill
   ```

5. **GitHub:** 그 주소를 엽니다. 1~2분 뒤 GitHub Actions가 실행 계획을 댓글로 올리면 아래 예측과 비교합니다. 그다음 **Merge pull request** → **Confirm merge**. main에 병합되면 GitHub Actions가 다시 plan하고, 삭제 검사 뒤 apply합니다(약 3분).
6. **Cloud Shell 터미널:** main으로 돌아와 최신으로 맞춥니다.

   ```bash
   git switch main && git pull
   ```

**예측.** pull request의 댓글 **Terraform plan**:

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

그 위에 `This plan destroys nothing. Merging to main plans it again and applies it.` 환경 변수 목록은 순서가 없는 집합이라, 값 하나가 바뀌면 그 항목을 지우고(`-`) 새로 추가하는(`+`) 것으로 표시됩니다.

**어디서 볼까.** **GitHub:** pull request의 댓글과 **Checks** 탭의 `pr-plan`. 병합 뒤에는 **Actions** → 맨 위 실행 → `infra` 작업. `build`와 `deploy`는 건너뜁니다(`infra/`만 바뀜).

**막히면.**
- `git diff`에 아무것도 나오지 않으면 파일이 저장되지 않은 것입니다. 편집기에서 저장하고 다시 `git diff`.
- `git push`가 비밀번호를 물으면 `gh auth setup-git`을 실행한 뒤 다시 push.

**이유.** 실무에서 인프라 코드는 편집기에서 브랜치 위에 수정하고, diff로 확인하고, plan으로 미리 본 뒤, 사람이 실행 계획을 읽은 pull request를 거쳐서만 main에 들어갑니다. pull request의 plan은 읽기 전용 계정(`tickets-terraform-plan`)이 상태를 잠그지 않고 만들고, apply는 main에 병합된 뒤 쓰기 권한이 있는 계정(`tickets-terraform`)만 하고, 이 계정도 누가 무엇을 할 수 있는지는 바꿀 수 없습니다(3단계에서 직접 적용한 기반). pull request의 로그인은 따로 있어서(`github-pr` 풀) apply나 배포 권한에 닿지 않습니다.

바뀌는 것은 web 서비스가 아니라 `housekeeping` 잡의 설정값입니다. 이 잡은 5분마다 실행되며, 행사 신청 오픈 15분 전부터는 web의 최소 인스턴스를 3으로, 그 밖에는 `web_min_instances`로 둡니다. Terraform은 기준값을 잡에 넘기고, web의 최소 인스턴스는 잡에게 맡깁니다(`run.tf`의 `ignore_changes`). 두 곳이 같은 값을 관리하면 서로 덮어쓰기 때문입니다.

## 7단계. 확인 (콘솔, Cloud Shell 터미널: 15분 대기 후 2분)

**할 일.**
1. 잡이 5분 안에 적용합니다. 바로 적용하려면 **콘솔:** ☰ → **Cloud Run → 작업** → `housekeeping` → **실행**.
2. 15분 이상 요청을 보내지 않은 뒤 **Cloud Shell 터미널**에서 5단계의 명령을 다시 실행합니다.

**예측.** 첫 요청도 약 0.1초(사전 점검에서는 0.12초). 세 줄이 같은 인스턴스입니다.

**어디서 볼까.**
- **콘솔:** ☰ → **Cloud Run** → `web` → **YAML**: 맨 위 `metadata`의 `run.googleapis.com/minScale: '1'`. 아래 `template` 안의 `autoscaling.knative.dev/minScale: '0'`은 리비전 수준의 값이고, 잡이 바꾸는 것은 서비스 수준의 값입니다.
- **콘솔:** `web` → **모니터링 가능성**(Observability) → **측정항목** → 컨테이너 인스턴스 수: 요청이 없어도 유휴 인스턴스 1

## 8단계. 콘솔에서 바꾼 설정: 드리프트 (콘솔, Cloud Shell 터미널: 5분)

**문제.** 오늘 밤 인기 행사의 신청이 열립니다. 당직 엔지니어가 평소보다 큰 몰림을 예상해, 사전 워밍 인스턴스를 3개에서 6개로 콘솔에서 직접 늘립니다. 오늘 밤에는 효과가 있습니다. 하지만 코드는 여전히 3이고, git에는 이 변경의 기록이 없습니다.

**할 일.**
1. **콘솔:** ☰ → **Cloud Run → 작업** → `housekeeping` → **수정** → 컨테이너의 **변수 및 보안 비밀** → `PREWARM_INSTANCES`를 `6`으로 → **업데이트**.
2. **Cloud Shell 터미널:** 내 저장소 폴더에서:

   ```bash
   terraform -chdir=infra plan
   ```

**예측.** Terraform이 자신이 하지 않은 변경을 찾아, 되돌리는 계획을 세웁니다.

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

**이유.** 실제 클라우드가 코드와 달라졌습니다. 이 차이가 드리프트입니다. plan은 매번 둘을 비교하고, 기준은 코드입니다. 다음 apply가 사전 워밍을 3으로 되돌리므로, 다음 큰 행사에는 따뜻한 인스턴스가 3개뿐이고 아무도 이유를 모릅니다. 오늘 밤을 위한 콘솔 수정은 합리적인 조치였지만, 계속 유지할 변경은 코드에 넣어야 합니다.

## 9단계. 되돌리기와 plan에 나타난 드리프트 (GitHub: 5분)

**문제.** 최소 인스턴스는 쉬는 동안에도 과금되므로 6단계의 변경을 되돌립니다.

**할 일.** GitHub에서:
1. 6단계에서 병합한 pull request 아래쪽 **Revert** → **Create pull request**.
2. 댓글의 실행 계획(아래)을 읽고 **Merge pull request** → **Confirm merge**.
3. **Cloud Shell 터미널:** `git pull`.

Cloud Shell 터미널로 하려면: 새 브랜치에서 `web_min_instances = 0`으로 바꿔 커밋하고 push한 뒤 `gh pr create --fill`.

**예측.** 댓글의 plan은 housekeeping 잡의 두 곳을 바꿉니다. 되돌리는 변경인 `WEB_MIN_INSTANCES`의 `"1"` → `"0"`과, git에서는 아무도 만들지 않은 `PREWARM_INSTANCES`의 `"6"` → `"3"`입니다. 둘 다 같은 잡이라 plan은 그대로 `Plan: 0 to add, 1 to change, 0 to destroy.`입니다.

**결정.** 드리프트는 보통 이렇게, 관계없는 변경의 plan에서 발견됩니다.
- 6이 오늘 밤만을 위한 값이었다면: 병합합니다. git이 기준이 되어 사전 워밍이 다시 3이 됩니다.
- 6을 유지해야 한다면: 먼저 코드에 넣습니다. 이 pull request에서 `infra/terraform.tfvars`에 `prewarm = { instances = 6, minutes_before = 15, minutes_after = 60 }`을 추가하면, plan 댓글에는 `WEB_MIN_INSTANCES`만 남습니다.

이 실습에서는 병합합니다.

**확인.** 실행이 끝난 뒤 **콘솔:** `housekeeping` → **수정** → **변수 및 보안 비밀**에 `PREWARM_INSTANCES` `3`, `WEB_MIN_INSTANCES` `0`. `git log --oneline`에 변경과 되돌림이 모두 남습니다.

**이유.** 콘솔에서 값을 다시 바꾸면 git에 기록이 남지 않습니다. 되돌림도 하나의 pull request로 같은 과정(plan 검토, 병합, 삭제 검사, apply)을 거칩니다. CI는 매번 코드 전체를 적용하므로, 손으로 한 변경은 조용히 남을 수 없습니다. git에 들어가거나, 다음 apply가 지웁니다.

## 10단계. 정리 (GitHub, Cloud Shell 터미널: 10분)

1. **GitHub:** 9단계의 되돌리기가 끝났는지 **Actions** 탭에서 확인합니다. 실행 중에 지우면 상태 잠금 오류가 납니다.
2. **GitHub:** 내 저장소 → **Settings → Secrets and variables → Actions → Variables**에서 `DEPLOY_ENABLED`를 지웁니다(Cloud Shell 터미널에서는 `gh variable delete DEPLOY_ENABLED`). 이후의 push가 지운 프로젝트에 배포하지 않게 합니다.
3. **Cloud Shell 터미널:** 앱을 먼저, 이어서 앱이 쓰는 기반을 지웁니다.

   ```bash
   terraform -chdir=infra destroy
   terraform -chdir=infra/bootstrap destroy
   ```

   `Plan: 0 to add, 0 to change, 51 to destroy.`를 읽고 `yes`(약 7분), 이어서 `55 to destroy`에 `yes`(약 2분).

상태 버킷 `프로젝트_ID-tfstate`는 Terraform 밖에서 만들었으므로 남습니다. 지우려면 **콘솔:** ☰ → **Cloud Storage → 버킷**에서 삭제합니다.
