# API 토큰은 환경 변수로만 받는다 — CLOUDFLARE_API_TOKEN (~/.config/clog-infra/cloudflare.env)
#   import·plan 은 읽기 전용 토큰(Zone·DNS·Zone Settings·Cloudflare Tunnel Read)으로 충분하다.
#   apply 로 실제 설정을 바꿀 때만 쓰기 토큰을 따로 만든다.
# 로컬: for f in ~/.config/clog-infra/*.env; do source "$f"; done  후 실행
provider "cloudflare" {}
