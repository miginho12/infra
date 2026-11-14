#!/usr/bin/env bash
# 버전 고정 실행(설치 없이 uv 로) — ansible-core 2.21.5(10-05). 2.22.0·2.21.6 은 11-02 배포라 2주 원칙으로 보류.
# 사용(사용자 터미널, sudo 비밀번호 필요):
#   ./run.sh --check --diff -K     # 바뀔 것만 보기 — 첫 도입은 changed=0 이어야 한다
#   ./run.sh --diff -K             # 적용
# 린트(sudo 불필요): ./run.sh lint
set -euo pipefail
cd "$(dirname "$0")"
CORE="ansible-core==2.21.5"
if [ "${1:-}" = "lint" ]; then
  shift
  exec uv tool run --from ansible-lint==26.10.1 --with "$CORE" ansible-lint "$@" site.yml
fi
exec uv tool run --from "$CORE" ansible-playbook site.yml "$@"
