# 버전 고정: 배포 직후 버전은 피하고 약 2주 지난 버전을 정확히 고정한다(ADR-095).
# 실제 설치 버전·해시는 .terraform.lock.hcl(커밋)이 기준 — 올릴 때는 여기와 lock 을 함께 바꾼다.
terraform {
  required_version = "= 1.17.1"

  required_providers {
    # 공식 provider(API v3, Main API key). 2.0.0 은 잘못 배포됐다 삭제된 버전이라 1.x 안에서만 쓴다.
    uptimerobot = {
      source  = "uptimerobot/uptimerobot"
      version = "= 1.13.0"
    }
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "= 2.3.0"
    }
  }
}
