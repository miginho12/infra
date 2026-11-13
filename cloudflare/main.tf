# Cloudflare — climb-log.com 의 진입점(DNS → Tunnel → 클러스터) 과 보안 관련 zone 설정 (ADR-096)
#
# 2026-11-14 대시보드의 기존 설정을 그대로 import(변경 0). ID 는 코드에 쓰지 않고 이름으로 조회한다
# (public 저장소). import 블록은 ID 가 들어가 커밋하지 않는 imports.tf 에만 두고, import 후 지운다.
#
# 관리하지 않는 것
# - 터널 자체(clog-prod): 읽기만(data). 리소스로 두면 API 가 tunnel_secret 을 돌려주지 않아 교체(재생성)
#   plan 이 나올 수 있고, 터널이 바뀌면 cloudflared 토큰이 무효 → 사이트 다운. 토큰은 gitops SealedSecret.
# - www.climb-log.com A 레코드: 터널이 아닌 외부 IP 로 521 — 처리 방식 결정 전(ADR-096 남은 일).
# - 다른 프로젝트 터널(k3s-home-server: gangazido.com).

locals {
  zone_name   = "climb-log.com"
  tunnel_name = "clog-prod"
  # cloudflared → 클러스터 안 frontend nginx (Service 이름은 gitops apps/clog-frontend)
  frontend_origin = "http://clog-frontend-prod.prod.svc.cluster.local:80"

  # 보안·HTTPS 관련만 코드로(바꿀 때는 plan → 승인 → apply). import 때(11-14) 값에서 바꾼 것:
  #   always_use_https off → on : http 요청이 그대로 200(로그인 POST 도 http 로 도착) — HSTS(nginx)는 첫 방문을 못 지킨다
  #   min_tls_version 1.0 → 1.2 : 1.0·1.1 퇴출. 앱 최소 Android 7·iOS 15 는 1.2 지원
  zone_settings = {
    ssl                      = "full"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
    security_level           = "medium"
  }
}

data "cloudflare_zone" "this" {
  filter = {
    name = local.zone_name
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared" "clog_prod" {
  account_id = data.cloudflare_zone.this.account.id
  filter = {
    name       = local.tunnel_name
    is_deleted = false
  }
}

# 사이트 본체: apex → 터널. 지우면 사이트가 바로 내려가므로 삭제 plan 자체를 막는다.
resource "cloudflare_dns_record" "apex" {
  zone_id = data.cloudflare_zone.this.zone_id
  name    = local.zone_name
  type    = "CNAME"
  content = "${data.cloudflare_zero_trust_tunnel_cloudflared.clog_prod.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # proxied 레코드는 자동(1)
  tags    = []
  settings = {
    flatten_cname = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# 터널 라우팅(원격 관리형). 마지막 규칙은 반드시 hostname 없는 catch-all.
# ⚠ provider #7395: 이 리소스를 destroy 해도 실제 라우팅은 남는다("1 destroyed" 를 믿지 말 것).
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "clog_prod" {
  account_id = data.cloudflare_zone.this.account.id
  tunnel_id  = data.cloudflare_zero_trust_tunnel_cloudflared.clog_prod.id
  source     = "cloudflare"

  config = {
    ingress = [
      {
        hostname = local.zone_name
        service  = local.frontend_origin
      },
      {
        service = "http_status:404"
      },
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = data.cloudflare_zone.this.zone_id
  setting_id = each.key
  value      = each.value
}
