variable "discord_webhook_url" {
  description = "UptimeRobot 알림용 Discord 웹훅(#uptime 채널). TF_VAR_discord_webhook_url 로만 넣는다."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^https://discord\\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$", var.discord_webhook_url))
    error_message = "Discord 웹훅 URL 형식이 아니다."
  }
}
