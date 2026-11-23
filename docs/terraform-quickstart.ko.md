# Terraform과 GitOps 실습 빠른 시작

새 Google Cloud 프로젝트에 Cloud Ticketing 전체를 Terraform으로 만들고, 설정 한 줄(콜드 스타트)을 git으로 바꿉니다. 단계별 설명은 [terraform-lab.ko.md](terraform-lab.ko.md)에 있습니다. English: [terraform-quickstart.en.md](terraform-quickstart.en.md).

파일은 **Cloud Shell 편집기**에서 고치고, 명령은 **Cloud Shell 터미널**에서 실행하며, **GitHub**는 브라우저의 GitHub 웹사이트(검토, 병합, 되돌리기)입니다. 실습 스크립트는 한 번만 하는 준비용 `./lab` 명령 두 개뿐이고, 그 뒤는 terraform, git, gcloud, curl, GitHub로 합니다. 준비물은 결제가 연결된 프로젝트, GitHub 계정, Cloud Shell입니다. 준비에 약 30분, 콜드 스타트 확인에 15분 대기가 두 번 필요합니다.

## 1. 준비 (한 번)

1. **콘솔:** 프로젝트를 만들고 결제를 연결합니다. **GitHub:** `joyrla/gdgoc-tickets-lab` → **Use this template** → 비공개 저장소 `gdgoc-tickets-iac`.
2. **Cloud Shell 터미널**(콘솔 오른쪽 위 **Cloud Shell 활성화**, >_): GitHub에 로그인하고, 내 저장소를 받아 프로젝트에 연결합니다.

   ```bash
   gh auth login --hostname github.com --git-protocol https --web --scopes workflow   # github.com/login/device에 코드 입력
   gh repo clone 내_GitHub_ID/gdgoc-tickets-iac        # 내 비공개 저장소
   cd gdgoc-tickets-iac
   ./lab bootstrap 프로젝트_ID                          # Terraform 1.9.8, 설정 파일 두 개, 상태 버킷, init
   source ~/.bashrc                                   # 한 번: 이 터미널이 Terraform을 찾음(Cloud Shell에 기본 설치 없음)
   ```

3. **Cloud Shell 터미널: 기반 생성**(API, 서비스 계정, 역할, GitHub의 키 없는 로그인). 누가 무엇을 할 수 있는지를 정하므로 직접 적용합니다.

   ```bash
   cd infra/bootstrap
   terraform plan     # 먼저 읽기: Plan: 55 to add, 0 to change, 0 to destroy.
   terraform apply    # 같은 계획이 다시 나오면 yes 입력. 약 2분
   ```

4. **Cloud Shell 터미널: 앱은 GitHub Actions에 맡기기.** 이제부터 git의 설정 파일이 원하는 상태의 기준입니다(GitOps). 첫 push에서 GitHub Actions가 권한을 바꿀 수 없는 계정으로 앱을 만들고 배포합니다.

   ```bash
   cd ../..
   ./lab connect                                      # GitHub Actions 변수, 배포 켜기
   git add infra/terraform.tfvars infra/bootstrap/terraform.tfvars
   git commit -m "Terraform settings for my project"
   git push                                           # Actions: Plan: 51 to add, apply, 이어서 앱 배포(약 20분)
   terraform -chdir=infra output -raw web_url         # 사이트 주소(실행이 끝난 뒤)
   ```

   새 프로젝트에서는 `infra` 작업에 경고(Eventarc나 Firestore의 준비 미완료)가 나오고, 1분 뒤 남은 것을 스스로 다시 적용할 수 있습니다. 그래도 실패하면 GitHub에서: 그 실행 → **Re-run jobs** → **Re-run failed jobs**.

## 2. 콜드 스타트: Terraform 설정 한 줄

**이제부터 plan과 apply가 실행되는 곳**
- **pull request:** GitHub Actions가 읽기 전용 계정으로 plan을 만들어 댓글로 올립니다. 아직 아무것도 바뀌지 않습니다.
- **main에 병합:** GitHub Actions가 다시 plan하고, 삭제가 있으면 멈추고, 없으면 apply합니다.
- **Cloud Shell:** 기반의 apply(1. 준비의 3번), 미리 보고 싶을 때의 `terraform -chdir=infra plan`.

| 단계 | 곳: 할 일 | 결과 |
|---|---|---|
| 측정 | **Cloud Shell 터미널:** 15분 이상 요청 없이 둔 뒤 `URL=$(terraform -chdir=infra output -raw web_url)` 다음 `for i in 1 2 3; do curl -s -o /dev/null -w '%{time_total}s  %header{x-served-by}\n' "$URL/health"; done` | 첫 요청 약 4~6초, 이후 약 0.1초 |
| 브랜치 | **Cloud Shell 터미널:** `git switch main && git pull` 다음 `git switch -c min-instances-1` | |
| 변경 | **Cloud Shell 편집기:** `infra/terraform.tfvars` → `web_min_instances = 1` → 저장(Ctrl+S) | 터미널의 `git diff`에 `0` → `1` |
| 미리 보기 | **Cloud Shell 터미널:** `terraform -chdir=infra plan` | `Plan: 0 to add, 1 to change, 0 to destroy.`(적용되지 않음) |
| pull request | **Cloud Shell 터미널:** `git commit -am "web: keep one instance warm"`, `git push -u origin min-instances-1`, `gh pr create --fill` | pull request 주소 |
| 검토 | **GitHub:** 1~2분 뒤 pull request에 올라오는 plan 댓글 | `Plan: 0 to add, 1 to change, 0 to destroy.` housekeeping 잡의 `WEB_MIN_INSTANCES`가 "0"에서 "1"로, "This plan destroys nothing" |
| 적용 | **GitHub:** **Merge pull request** → Confirm merge. 이어서 Cloud Shell 터미널에서 `git switch main && git pull` | Actions: 검사, plan, 삭제 검사, apply. 빌드와 배포는 건너뜀(약 3분) |
| 바로 반영 | **Cloud Shell 터미널:** `gcloud run jobs execute housekeeping --region asia-northeast3 --wait` 또는 콘솔 → Cloud Run → 작업 → `housekeeping` → 실행(그대로 두면 5분 안에 반영) | |
| 확인 | **Cloud Shell 터미널:** `gcloud run services describe web --region asia-northeast3 --format=yaml \| grep minScale` | `run.googleapis.com/minScale: '1'`(서비스 수준. `autoscaling.knative.dev` 줄은 리비전 자체의 값) |
| 다시 측정 | **Cloud Shell 터미널:** 15분 이상 요청 없이 둔 뒤 같은 `curl` 반복 | 첫 요청 약 0.1초, 같은 인스턴스 |
| 드리프트 | **콘솔:** Cloud Run → 작업 → `housekeeping` → 수정 → 변수 및 보안 비밀 → `PREWARM_INSTANCES` = `6` → 업데이트(큰 행사를 앞두고 당직자가 손으로 늘린 상황). 이어서 **Cloud Shell 터미널:** `terraform -chdir=infra plan` | `PREWARM_INSTANCES` `"6"` → `"3"`, `1 to change`: Terraform 밖에서 생긴 변경(드리프트)이고, 다음 apply가 되돌림 |
| 되돌리기 | **GitHub:** 병합된 pull request에서 **Revert** → Create pull request → plan 확인 → Merge | plan이 두 값을 바꿈: `WEB_MIN_INSTANCES` `"1"` → `"0"`(되돌림), `PREWARM_INSTANCES` `"6"` → `"3"`(드리프트). 6을 유지하려면 이 pull request에서 `infra/terraform.tfvars`의 `prewarm`에 넣음. 여기서는 병합. 최소 인스턴스는 쉬는 동안에도 과금 |

**plan에서 web 서비스가 아니라 잡이 바뀌는 이유.** 5분마다 실행되는 housekeeping 잡이 web의 최소 인스턴스를 설정합니다. 신청 오픈 15분 전부터는 3, 그 밖에는 `web_min_instances`입니다. Terraform은 이 값을 잡에 넘기고, 서비스의 해당 필드는 무시합니다(`run.tf`의 `ignore_changes`). 두 곳이 같은 값을 관리하면 서로 덮어쓰기 때문입니다.

## 3. 정리

먼저 GitHub의 **Actions**에서 되돌리기 실행이 끝났는지 확인합니다(실행 중에 지우면 상태 잠금 오류). 그다음 Cloud Shell 터미널에서:

```bash
gh variable delete DEPLOY_ENABLED            # 배포 끄기: 이후의 push가 지운 프로젝트에 배포하지 않음
terraform -chdir=infra destroy               # 앱: 51 to destroy. yes 입력, 약 7분
terraform -chdir=infra/bootstrap destroy     # 이어서 기반: 55 to destroy. 약 2분
```

상태 버킷 `프로젝트_ID-tfstate`는 Terraform 밖에서 만들었으므로 남습니다. 더 쓰지 않으면 Cloud Storage에서 삭제합니다.
