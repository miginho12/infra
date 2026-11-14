# infra

clog 의 클러스터 **밖** 인프라를 Terraform 으로 관리한다. 클러스터 안(k3s 앱·모니터링)은 `gitops` 저장소(ArgoCD)가 맡는다.

| 폴더 | 내용 |
|---|---|
| `uptime/` | 외부 업타임 감시 — UptimeRobot 키워드 감시 + Healthchecks.io dead-man switch(Alertmanager Watchdog) |
| `cloudflare/` | 진입점 — `climb-log.com` DNS(→ Tunnel)·터널 라우팅·보안 zone 설정 (대시보드 기존 설정을 import, 아래) |

폴더마다 state 가 따로다(한쪽 apply 가 다른 쪽을 건드리지 않게).

## 원칙

- **비밀은 Git 에 없다.** API key·웹훅 URL 은 환경 변수로만 받는다(`~/.config/clog-infra/*.env`, 권한 600).
- **state 는 로컬.** `*.tfstate` 는 웹훅·ping URL 을 평문으로 담아 Git 에서 제외한다. 노트북이 매일 age 암호문으로 받아 간다(아래 백업).
- **CI 는 `fmt`·`validate` 만.** `plan`·`apply` 는 로컬에서, plan 을 확인·승인한 다음 실행한다.
- **버전 고정.** Terraform·provider 는 정확한 버전으로 고정하고 `.terraform.lock.hcl` 을 커밋한다.

## 감시 구성 (`uptime/`)

```
[바깥에서 본다]  UptimeRobot ──5분── https://climb-log.com/api/health/ready   "status":"ready" 없으면 장애
                                └──── https://climb-log.com/                   id="root" 없으면 장애
                     └──▶ Discord #uptime

[안이 살아 있나]  Prometheus Watchdog(항상 firing) → Alertmanager ──5~6분마다 POST──▶ Healthchecks.io
                     timeout 10m + grace 5m → ping 이 약 15분 끊기면 ──▶ Discord #uptime + 메일
```

| 리소스 | 파일 | 비고 |
|---|---|---|
| `uptimerobot_integration.discord` | `uptimerobot.tf` | 웹훅은 `TF_VAR_discord_webhook_url` |
| `uptimerobot_monitor.this["backend"/"frontend"]` | `uptimerobot.tf` | 키워드, 리다이렉트 안 따라감, 다운 즉시·반복 없음 |
| `healthchecksio_check.alertmanager_watchdog` | `healthchecks.tf` | POST 만, Discord·메일 통합은 **UI 에서 만든 것**을 data source 로 참조(API 로 못 만듦) |

Alertmanager 쪽 설정은 gitops `apps/monitoring/values.yaml`(Watchdog route·`healthchecks` 수신처, `send_resolved: false`)과
`templates/sealed-secret-alertmanager-healthchecks.yaml`(ping URL).

## 사용

```bash
for f in ~/.config/clog-infra/*.env; do source "$f"; done   # ⚠ source *.env 를 한 번에 주면 첫 파일만 읽힌다
cd uptime
terraform init
terraform plan -out=tfplan          # 변경 내용 확인
terraform apply tfplan              # 승인 후
chmod 600 terraform.tfstate*        # Terraform 은 state 를 664 로 만든다 — 평문 비밀이라 잠근다
rm -f tfplan                        # plan 파일에도 비밀이 들어 있다
terraform plan                      # "No changes" 확인
```

비밀 파일(`~/.config/clog-infra/`, 폴더 700·파일 600):

| 파일 | 변수 | 어디서 |
|---|---|---|
| `uptimerobot.env` | `UPTIMEROBOT_API_KEY` | UptimeRobot → Integrations & API → **Main API key** |
| `healthchecks.env` | `HEALTHCHECKSIO_API_KEY` | Healthchecks.io 프로젝트 Settings → API Access → **API key**(읽기·쓰기, 발급 때 한 번만 보임) |
| `discord.env` | `TF_VAR_discord_webhook_url` | Discord `#uptime` 채널 → 연동 → 웹후크 (`uptimerobot`) |

provider 를 올릴 때는 `versions.tf` 를 바꾼 뒤 Pi(arm64)·CI(amd64) 해시를 함께 기록한다.

```bash
terraform init -upgrade
terraform providers lock -platform=linux_arm64 -platform=linux_amd64
```

## runbook

### 알림이 왔을 때

| 알림 | 뜻 | 먼저 볼 것 |
|---|---|---|
| UptimeRobot `clog backend ready` DOWN | 공개 주소로 backend 가 준비 안 됨 | `curl -s https://climb-log.com/api/health/ready` · `kubectl -n prod get pod` · cloudflared |
| UptimeRobot `clog frontend` DOWN | 공개 주소로 SPA 가 안 나옴 | `curl -sI https://climb-log.com/` · nginx-prod·clog-frontend-prod Pod · cloudflared |
| 둘 다 DOWN | Pi·인터넷·Cloudflare Tunnel 전체 | Pi 전원·네트워크(Tailscale 접속 되는지), `kubectl -n prod get pod`, Cloudflare 상태 |
| Healthchecks `clog alertmanager watchdog` DOWN | **클러스터 안 알림이 멈췄을 수 있음**(Prometheus·Alertmanager·Pi·네트워크) | `kubectl -n monitoring get pod` · Alertmanager 로그 · Watchdog 이 `healthchecks` 로 가는지(아래) |

공개 주소 장애는 UptimeRobot 이 5분 안에, 클러스터 안 알림 경로 정지는 Healthchecks 가 약 15분 안에 알린다.

```bash
# Watchdog 이 어디로 가는지 (healthchecks 여야 정상)
curl -s 'http://localhost:30903/api/v2/alerts?filter=alertname%3D%22Watchdog%22' | python3 -c 'import sys,json; print([r["name"] for a in json.load(sys.stdin) for r in a["receivers"]])'
```

### Healthchecks 체크를 다시 만들면

ping URL 이 바뀐다 → SealedSecret 을 다시 봉인해야 한다(안 하면 Watchdog ping 이 옛 URL 로 가 15분 뒤 DOWN).

```bash
terraform output -raw watchdog_ping_url | kubectl create secret generic alertmanager-healthchecks -n monitoring \
  --from-file=url=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --controller-namespace sealed-secrets --controller-name sealed-secrets-controller -o yaml
# → gitops apps/monitoring/templates/sealed-secret-alertmanager-healthchecks.yaml 의 encryptedData 교체·push
```

### apply 가 중간에 실패하면

성공한 리소스만 state 에 남는다 → `terraform plan` 을 다시 만들면 남은 것만 나온다. 확인 후 재시도.
(2026-11-12 첫 apply 에서 UptimeRobot API 가 backend 감시만 `500 (code 000-013)` — 재 plan·apply 로 생성, 서버에 반쯤 만들어진 감시 없음.)

### state 백업·복구

- **백업:** 노트북 `pull-backup.ps1` 이 매일 stack 마다(`$TfStacks` = uptime·cloudflare) `ssh … tfstate <stack>` 로 암호문을 받아
  크기·SHA256·version·serial 을 검증하고 `%USERPROFILE%\clog-backup\tfstate\tfstate-<stack>-<serial>-<sha12>.json.age` 로 저장한 뒤 `ack-tfstate`.
  이름이 내용 해시라 state 가 바뀔 때만 새 파일. stack 별로 72h 동안 ack 가 없으면 `ClogTfstateBackupStale`, 지표가 없으면 `MetricMissing`.
  **새 stack(폴더)을 만들면** gitops `scripts/backup-export.sh` 의 `TFSTATE_STACKS`, `pull-backup.ps1` 의 `$TfStacks`, 알림 룰 MetricMissing 에 함께 추가.
- **복구(노트북 사본):** `age -d -i keys\age.key tfstate-<stack>-…json.age > <stack>/terraform.tfstate` → `terraform plan` 이 No changes.
- **복구(사본도 없을 때):** 4개 리소스 모두 import 가능.
  ```bash
  terraform import uptimerobot_integration.discord <integration id>
  terraform import 'uptimerobot_monitor.this["backend"]' <monitor id>
  terraform import 'uptimerobot_monitor.this["frontend"]' <monitor id>
  terraform import healthchecksio_check.alertmanager_watchdog <check uuid>
  ```
  ID 는 UptimeRobot·Healthchecks 대시보드(또는 API 목록)에서.

### 알림 시험 (prod 를 건드리지 않고)

운영 리소스는 그대로 두고, 커밋하지 않는 임시 파일(`uptime/alert_test.tf`)로 실패하는 감시를 만든다.

- UptimeRobot: 같은 URL + 페이지에 없는 키워드(`__clog_alert_test__`) → 첫 검사에서 DOWN
- Healthchecks: timeout 60 + grace 60 체크에 한 번 POST ping 후 멈춤 → 2분 뒤 DOWN

알림 확인 후 파일 삭제 → plan(삭제 2) → apply → `terraform plan` No changes.
2026-11-12 결과: UptimeRobot DOWN 약 1.5분, Healthchecks DOWN 2분, Discord `#uptime`·메일 모두 수신.

## cloudflare/ — 진입점

```
https://climb-log.com ─ DNS CNAME(proxied) ─▶ Tunnel clog-prod ─ cloudflared(prod, 2 replica) ─▶ clog-frontend-prod:80
                                                └ 그 밖의 hostname → http_status:404
```

| 리소스 | 관리 | 비고 |
|---|---|---|
| `cloudflare_dns_record.apex` | ✅ | `prevent_destroy` — 지우면 사이트가 바로 내려간다 |
| `cloudflare_zero_trust_tunnel_cloudflared_config.clog_prod` | ✅ | `prevent_destroy`. ⚠ provider #7395: destroy 해도 실제 라우팅은 남는다 |
| `cloudflare_zone_setting.this[...]` | ✅ | ssl·always_use_https(**on**, 11-14)·min_tls_version(**1.2**, 11-14)·tls_1_3·automatic_https_rewrites·security_level |
| 터널 `clog-prod` | 읽기(data) | 리소스로 두면 `tunnel_secret` 을 API 가 안 돌려줘 교체 plan 위험 → 토큰은 gitops SealedSecret |
| `cloudflare_dns_record.www` | ✅ | redirect 전용 — proxied A `192.0.2.1`(RFC 5737 예약, 라우팅 안 됨). 11-14 이전엔 소유 불명 외부 IP 로 521 |
| `cloudflare_ruleset.redirect` | ✅ | `http_request_dynamic_redirect`: `www.climb-log.com/*` → `https://climb-log.com/*` 301(쿼리 유지). 엣지에서 끝나 원 서버로 안 감 |
| 터널 `k3s-home-server` | ❌ | 다른 프로젝트 |

- ID 는 코드에 쓰지 않는다(public 저장소) — zone·터널을 이름으로 조회.
- 토큰: `cloudflare.env` 의 `CLOUDFLARE_API_TOKEN`. **plan·import 는 읽기 전용 토큰**(Zone·DNS·Zone Settings·Single Redirect Read +
  Account Cloudflare Tunnel Read, zone 은 climb-log.com 만 보임 확인). 실제로 바꿀 때만 쓰기 토큰(`cloudflare.write` — `.env` 가 아니라
  기본 반복문에 안 들어감, Zone Settings·DNS·Single Redirect Edit + Tunnel Read, **만료 짧게**)을 `source` 해서 apply 하고 끝나면 폐기.
  ⚠ 쓰기 토큰에도 Tunnel Read 가 필요(data source 조회), 읽기 토큰에도 Single Redirect Read 가 필요(ruleset 조회) — 없으면 plan 이 403.
  ruleset 은 plan 때 `dry_run=true` 로 검증되며 이때도 쓰기 권한이 필요(읽기 토큰 plan 은 경고만, 생성은 apply 때 서버가 검증).
- 대시보드에서 직접 바꾸면 `terraform plan` 에 차이(drift)로 나온다 → 코드로 옮기거나 되돌린다.
- **drift 주기 점검**: `scripts/drift-check.sh`(uptime·cloudflare, 읽기 전용 plan `-lock=false`)를 매일 07:00 KST user crontab 으로
  실행(`scripts/crontab.txt` → `crontab scripts/crontab.txt`) → textfile 지표 `clog_terraform_drift{stack}` 등 →
  알림 TerraformDriftDetected·CheckFailing·CheckStale(36h)·MetricMissing. 마지막 plan 출력: `~/.local/state/clog-infra/drift-<stack>.log`.
  linger 가 꺼져 있어 systemd user timer 대신 cron(로그인 무관).

### 새 리소스를 import 할 때

1. `cf-terraforming generate --zone <zone_id> --resource-type <type> --terraform-binary-path $(command -v terraform)` 로 초안
   (출력에 ID 가 있으니 저장소 밖에), 코드로 옮길 때 ID 는 data source 참조로 바꾼다.
2. `imports.tf`(.gitignore — 실제 ID) 에 `import { to = … id = "…" }`.
3. `terraform plan` 이 **"N to import, 0 to add, 0 to change, 0 to destroy"** 가 될 때까지 코드를 실제 값에 맞춘다.
4. apply(import 만이라 Cloudflare 로 쓰기 없음) → `rm imports.tf` → `chmod 600 terraform.tfstate*` → `terraform plan` No changes.

2026-11-14 첫 import: 8개(DNS 1·터널 라우팅 1·zone 설정 6), plan 8 to import·0 변경 → apply 후 No changes, 사이트 200 유지.
같은 날 변경: always_use_https on·min_tls 1.2(TLS 1.0·1.1 거부까지 엣지 반영 수십 초), www → apex 301(www 레코드 import + 대상 교체 + ruleset 생성).
