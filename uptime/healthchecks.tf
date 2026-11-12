# dead-man switch — 클러스터 안 알림 경로 자체가 죽은 것을 잡는다(ADR-095).
# Prometheus 의 Watchdog 알림(항상 firing)을 Alertmanager 가 주기적으로 여기에 ping 한다.
# Prometheus·Alertmanager·Pi·네트워크 중 하나라도 멈추면 ping 이 끊기고 → Healthchecks 가 알린다.
#
# ping 은 Alertmanager Watchdog route 의 repeat_interval 5m(group_interval 1m 단위라 실제 5~6분)마다 온다(gitops apps/monitoring/values.yaml).
# timeout 10m(간격의 약 2배라 한 번 늦어도 "늦음" 표시 없음) + grace 5m → 마지막 ping 후 약 15분 조용하면 알림. Pi 재부팅(수 분)은 넘기고,
# 공개 주소 장애는 UptimeRobot(5분)이 먼저 잡는다.

data "healthchecksio_channel" "discord" {
  kind = "discord" # Healthchecks UI 에서 만든 통합(API 로는 만들 수 없다)
}

data "healthchecksio_channel" "email" {
  kind = "email" # Discord 가 같이 막혀도 받도록 메일도
}

resource "healthchecksio_check" "alertmanager_watchdog" {
  name = "clog alertmanager watchdog"
  desc = "Prometheus Watchdog → Alertmanager → 여기. 끊기면 클러스터 안 알림이 멈춘 것."
  tags = ["clog", "deadman"]

  timeout = 10 * 60
  grace   = 5 * 60
  methods = "POST" # Alertmanager webhook 은 POST — 링크 미리보기 등 GET 으로는 ping 되지 않게

  channels = [
    data.healthchecksio_channel.discord.id,
    data.healthchecksio_channel.email.id,
  ]
}

# ping URL 을 아는 사람은 누구나 "정상" 신호를 보낼 수 있다 → 출력은 sensitive, 클러스터엔 SealedSecret 으로.
output "watchdog_ping_url" {
  value     = healthchecksio_check.alertmanager_watchdog.ping_url
  sensitive = true
}
