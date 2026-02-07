## 📊 Architecture Diagrams

### System Overview

```
                Internet Users
                      │
                      ▼
              ┌────────────────┐
              │  Route53 DNS   │
              │ weather.mx...  │
              └───────┬────────┘
                      │
                      ▼
    ┌─────────────────────────────────────┐
    │   Application Load Balancer (ALB)   │
    │  • HTTPS → HTTP (TLS termination)   │
    │  • Health checks (/health)          │
    │  • IP allowlist (Security Group)    │
    └──────────────┬──────────────────────┘
                   │
       ┌───────────┼───────────┐
       │           │           │
       ▼           ▼           ▼
  ┌────────┐  ┌────────┐  ┌────────┐
  │ECS Task│  │ECS Task│  │ECS Task│
  │Weather │  │Weather │  │Weather │
  │Service │  │Service │  │Service │
  │Fargate │  │Fargate │  │Fargate │
  │  AZ-1  │  │  AZ-2  │  │  AZ-3  │
  └────────┘  └────────┘  └────────┘
       │           │           │
       └───────────┼───────────┘
                   │
       ┌───────────┼───────────┐
       │           │           │
       ▼           ▼           ▼
  ┌────────┐  ┌────────┐  ┌────────┐
  │ElastiCa│  │CloudWat│  │OpenWeat│
  │che Redis│  │ch Logs │  │her API │
  │(Cache) │  │(Observ)│  │(Extrnl)│
  └────────┘  └────────┘  └────────┘
```

### Request Flow

```
┌─────────────────────────────────────────────┐
│  1. User Request                             │
│     GET /weather/London                      │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  2. Middleware Chain                         │
│                                              │
│  a) Rate Limiter (100 RPS)                  │
│     └─> Reject if exceeded → 429            │
│                                              │
│  b) Correlation ID (UUID)                   │
│     └─> Add to context                      │
│                                              │
│  c) Metrics                                  │
│     └─> Track in_flight, duration           │
│                                              │
│  d) Logging (JSON + correlation_id)         │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  3. Handler                                  │
│                                              │
│  Check Redis Cache                          │
│  key: "weather:London"                      │
│  ttl: 5 minutes                             │
│                                              │
│  Cache HIT? ──Yes──> Return (5ms) ✓        │
│       │                                      │
│       No                                     │
│       │                                      │
│       ▼                                      │
│  Fetch from API                             │
│  ┌──────────────────────────┐              │
│  │ Retry Loop (max 3 times) │              │
│  │                           │              │
│  │ Attempt 1: Immediate      │              │
│  │ Attempt 2: 1s delay       │              │
│  │ Attempt 3: 2s delay       │              │
│  │                           │              │
│  │ Don't retry 4xx errors    │              │
│  └──────────────────────────┘              │
│                                              │
│  Store in Cache                             │
│  └─> cache.Set() [if fails, log & continue]│
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  4. Response                                 │
│     200 OK + JSON                            │
│     X-Correlation-ID: 550e8400...           │
└─────────────────────────────────────────────┘
```

### Monitoring Flow

```
   ECS Tasks (:8080/metrics)
         │
         │ scrape every 15s
         ▼
   ┌─────────────┐
   │ Prometheus  │
   │ (evaluate)  │
   └──────┬──────┘
          │ alert rules
          ▼
   ┌─────────────┐
   │AlertManager │
   │   (route)   │
   └──────┬──────┘
          │
     ┌────┴────┬──────┐
     │         │      │
     ▼         ▼      ▼
PagerDuty  Slack  Email
(Critical) (All)  (Warn)
```

### CI/CD Pipeline

```
Developer
    │
    │ git push
    ▼
┌───────────────────────────────┐
│     GitHub Actions            │
│                               │
│  1. Test & Lint               │
│     • go test -race           │
│     • golangci-lint           │
│                               │
│  2. Build & Push              │
│     • docker build            │
│     • tag SHA                 │
│     • push ECR                │
│                               │
│  3. Terraform (main only)     │
│     • plan                    │
│     • apply                   │
│                               │
│  4. Deploy                    │
│     • update service          │
│     • wait stable             │
│     • health check            │
└───────────────┬───────────────┘
                │
                ▼
          Production ECS
```

### Data Flow Paths

```
Fast Path (Cache HIT):
User → ALB → ECS → Redis → Response
                    (5ms)

Slow Path (Cache MISS):
User → ALB → ECS → OpenWeather API → Response
                   (retry logic)      (500ms)
                   ↓
                 Redis
                (cache for next)