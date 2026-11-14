#!/usr/bin/env bash
# Terraform drift 주기 점검 (2026-11-14) — 대시보드·API 로 직접 바꾼 설정(코드와 실제의 차이)을 매일 찾는다.
#
# stack 마다 `terraform plan -detailed-exitcode` (읽기만: -lock=false, apply 없음) →
# node-exporter textfile 지표 → Prometheus 알림(gitops apps/monitoring: TerraformDrift*).
#   clog_terraform_drift{stack}                       0 = 코드 = 실제, 1 = 차이 있음
#   clog_terraform_drift_check_success{stack}         1 = plan 이 끝까지 돎, 0 = 실패(토큰 만료·API 오류 등)
#   clog_terraform_drift_last_run_timestamp_seconds   점검 시각(멈춤 감지)
# 마지막 plan 출력은 ~/.local/state/clog-infra/drift-<stack>.log (600) — 알림이 오면 여기부터 본다.
#
# 실행: user crontab (scripts/crontab.txt). 수동: scripts/drift-check.sh [stack...]
# 토큰: ~/.config/clog-infra/*.env — cloudflare 는 **읽기 전용** 토큰(cloudflare.env)만 쓰인다
#   (쓰기 토큰은 cloudflare.write 로 .env 가 아니라 여기 들어오지 않는다).

set -uo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACKS=("$@"); [ ${#STACKS[@]} -gt 0 ] || STACKS=(uptime cloudflare)
METRICS_DIR="${METRICS_DIR:-/var/lib/node_exporter/textfile_collector}"
LOG_DIR="${LOG_DIR:-$HOME/.local/state/clog-infra}"
ENV_DIR="${ENV_DIR:-$HOME/.config/clog-infra}"
mkdir -p "$LOG_DIR"

for f in "$ENV_DIR"/*.env; do [ -r "$f" ] && source "$f"; done

out=""
for st in "${STACKS[@]}"; do
  case "$st" in uptime|cloudflare) ;; *) echo "drift-check: 알 수 없는 stack $st" >&2; exit 2 ;; esac
  log="$LOG_DIR/drift-$st.log"
  # plan 이 state 를 갱신하지 않게 -refresh 는 하되 저장은 안 함(plan 은 원래 state 를 쓰지 않는다), 잠금도 안 잡음
  ( cd "$ROOT/$st" && timeout 600 terraform plan -input=false -no-color -lock=false -detailed-exitcode ) > "$log" 2>&1
  rc=$?
  case $rc in
    0) drift=0; ok=1 ;;
    2) drift=1; ok=1 ;;
    *) drift=0; ok=0 ;;   # 실패 시 drift 는 판단 불가 → success=0 알림이 맡는다
  esac
  echo "$(date -u +%FT%TZ) drift-check stack=$st rc=$rc drift=$drift ok=$ok"
  out+="clog_terraform_drift{stack=\"$st\"} $drift"$'\n'
  out+="clog_terraform_drift_check_success{stack=\"$st\"} $ok"$'\n'
  out+="clog_terraform_drift_last_run_timestamp_seconds{stack=\"$st\"} $(date -u +%s)"$'\n'
done

# 수동으로 stack 하나만 돌리면 다른 stack 줄이 사라진다 → 전부 돌린 경우에만 지표 파일을 쓴다
if [ ${#STACKS[@]} -eq 2 ]; then
  PROM="$METRICS_DIR/clog_terraform_drift.prom"
  {
    echo "# HELP clog_terraform_drift 1 = Terraform 코드와 실제 인프라가 다르다(plan 에 변경 있음)"
    echo "# TYPE clog_terraform_drift gauge"
    echo "# HELP clog_terraform_drift_check_success 1 = drift 점검 plan 이 끝까지 돌았다"
    echo "# TYPE clog_terraform_drift_check_success gauge"
    echo "# HELP clog_terraform_drift_last_run_timestamp_seconds drift 점검을 마지막으로 돌린 시각"
    echo "# TYPE clog_terraform_drift_last_run_timestamp_seconds gauge"
    printf '%s' "$out"
  } > "$PROM.tmp"
  # node-exporter(uid 65534) 가 읽어야 해서 644, 반쯤 쓴 파일을 읽지 않게 mv 로 교체
  chmod 644 "$PROM.tmp" && mv "$PROM.tmp" "$PROM"
fi
