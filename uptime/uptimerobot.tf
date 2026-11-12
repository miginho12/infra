# 외부 업타임 감시 — 클러스터 밖(UptimeRobot)에서 공개 주소를 본다.
# 클러스터 안 Prometheus 는 Pi·인터넷·Cloudflare Tunnel 이 통째로 죽으면 알릴 수 없어서 따로 둔다(ADR-095).

locals {
  base_url = "https://climb-log.com"

  # 상태 코드만 보면 오류 페이지·SPA 기본 응답도 200 이라 통과한다 → 본문 키워드까지 본다.
  monitors = {
    backend = {
      name    = "clog backend ready"
      path    = "/api/health/ready" # ⚠ /health/ready 는 frontend SPA 가 200 으로 받는다
      keyword = "\"status\":\"ready\""
    }
    frontend = {
      name    = "clog frontend"
      path    = "/"
      keyword = "id=\"root\""
    }
  }
}

resource "uptimerobot_integration" "discord" {
  name                     = "Discord #uptime"
  type                     = "discord"
  value                    = var.discord_webhook_url
  enable_notifications_for = 1     # 다운·복구 모두
  ssl_expiration_reminder  = false # 인증서는 Cloudflare 가 자동 갱신
}

resource "uptimerobot_monitor" "this" {
  for_each = local.monitors

  name     = each.value.name
  type     = "KEYWORD"
  url      = "${local.base_url}${each.value.path}"
  interval = 300 # 무료 플랜 최소 5분
  timeout  = 30

  http_method_type    = "GET"
  follow_redirections = false # 로그인·차단 페이지로 돌려보내는 것도 장애로 본다

  # 키워드가 **없으면** 장애
  keyword_type      = "ALERT_NOT_EXISTS"
  keyword_value     = each.value.keyword
  keyword_case_type = "CaseSensitive"

  assigned_alert_contacts = [
    {
      alert_contact_id = uptimerobot_integration.discord.id
      threshold        = 0 # 다운 확인 즉시
      recurrence       = 0 # 반복 알림 없음(복구 알림은 옴)
    }
  ]
}

output "monitors" {
  value = { for k, m in uptimerobot_monitor.this : k => { id = m.id, url = m.url } }
}
