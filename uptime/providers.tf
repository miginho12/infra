# API key 는 코드·tfvars 에 두지 않고 환경 변수로만 받는다(Git 에 비밀이 들어가지 않게).
#   UPTIMEROBOT_API_KEY      — UptimeRobot Main API key
#   HEALTHCHECKSIO_API_KEY   — Healthchecks.io 프로젝트 읽기·쓰기 key
# 로컬: for f in ~/.config/clog-infra/*.env; do source "$f"; done  후 실행 (source 에 *.env 를 한 번에 주면 첫 파일만 읽힌다)
provider "uptimerobot" {}

provider "healthchecksio" {}
