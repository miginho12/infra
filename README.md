# infra

clog 의 클러스터 **밖** 인프라를 Terraform 으로 관리한다. 클러스터 안(k3s 앱·모니터링)은 `gitops` 저장소(ArgoCD)가 맡는다.

| 폴더 | 내용 |
|---|---|
| `uptime/` | 외부 업타임 감시 — UptimeRobot 키워드 감시 + Healthchecks.io dead-man switch(Alertmanager Watchdog) |

## 원칙

- **비밀은 Git 에 없다.** API key·웹훅 URL 은 환경 변수로만 받는다(`~/.config/clog-infra/*.env`, 권한 600).
- **state 는 로컬.** `*.tfstate` 는 웹훅 URL 등 비밀을 평문으로 담아 Git 에서 제외하고 노트북 age 백업으로 보관한다.
- **CI 는 `fmt`·`validate` 만.** `plan`·`apply` 는 로컬에서, plan 을 확인·승인한 다음 실행한다.
- **버전 고정.** Terraform·provider 는 정확한 버전으로 고정하고 `.terraform.lock.hcl` 을 커밋한다.

## 사용

```bash
for f in ~/.config/clog-infra/*.env; do source "$f"; done   # UPTIMEROBOT_API_KEY, HEALTHCHECKSIO_API_KEY, TF_VAR_discord_webhook_url
cd uptime
terraform init
terraform plan -out=tfplan          # 변경 내용 확인
terraform apply tfplan              # 승인 후
terraform plan                      # "No changes" 확인
```

provider 를 올릴 때는 `versions.tf` 를 바꾼 뒤 Pi(arm64)·CI(amd64) 해시를 함께 기록한다.

```bash
terraform init -upgrade
terraform providers lock -platform=linux_arm64 -platform=linux_amd64
```
