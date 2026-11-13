# 버전 고정: 배포 직후 버전은 피하고 약 2주 이상 지난 버전을 정확히 고정한다(ADR-095·096).
# 5.29.0 은 11-11 배포라 제외. 올릴 때는 여기와 .terraform.lock.hcl 을 함께 바꾼다.
terraform {
  required_version = "= 1.17.1"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.28.1"
    }
  }
}
