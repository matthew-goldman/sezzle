# Service Level Objectives (SLOs) and Indicators (SLIs)

## Overview

This document defines the Service Level Objectives (SLOs) and Service Level Indicators (SLIs) for the Weather Alert Service. These metrics are used to measure service reliability and trigger alerts when performance degrades.

## SLI Definitions

### 1. Availability SLI

**Definition**: Percentage of requests that complete successfully (non-5xx responses)

**Measurement**:
```promql
sum(rate(weather_request_success_total{success="true"}[30d]))
/
sum(rate(weather_request_success_total[30d]))
```

**Target**: 99.9% over 30 days

**Error Budget**: 0.1% = 43.2 minutes per month

### 2. Latency SLI

**Definition**: Percentage of requests completed within latency threshold

**Measurement** (P95 < 500ms):
```promql
histogram_quantile(0.95,
  sum(rate(weather_http_request_duration_seconds_bucket[5m])) by (le)
) < 0.5
```

**Measurement** (P99 < 1s):
```promql
histogram_quantile(0.99,
  sum(rate(weather_http_request_duration_seconds_bucket[5m])) by (le)
) < 1.0
```

**Target**:
- P95: < 500ms (95% of requests)
- P99: < 1s (99% of requests)

### 3. Throughput SLI

**Definition**: Requests processed per second

**Measurement**:
```promql
sum(rate(weather_http_requests_total[5m]))
```

**Target**: Maintain baseline throughput with <10% degradation during incidents

## SLO Targets

| SLI | Objective | Measurement Window | Error Budget |
|-----|-----------|-------------------|--------------|
| **Availability** | 99.9% | 30 days | 43.2 min/month |
| **Latency (P95)** | < 500ms | 5 minutes | 5% can exceed |
| **Latency (P99)** | < 1s | 5 minutes | 1% can exceed |
| **Error Rate** | < 0.1% | 5 minutes | 0.1% of requests |

## Error Budget Policies

### Error Budget Consumption Tiers

#### Tier 1: Healthy (0-25% of budget consumed)
- **Status**: Normal operations
- **Actions**: 
  - Continue feature development
  - Monitor trends
  - No restrictions

#### Tier 2: Warning (25-75% of budget consumed)
- **Status**: Elevated caution
- **Actions**:
  - Increase monitoring vigilance
  - Review recent changes
  - Consider postponing risky deployments
  - No feature freeze yet

#### Tier 3: Critical (75-100% of budget consumed)
- **Status**: Budget exhaustion imminent
- **Actions**:
  - **FREEZE** non-critical feature deployments
  - Focus on reliability improvements
  - Root cause analysis of incidents
  - Reduce deployment frequency
  - Emergency changes only

#### Tier 4: Exhausted (>100% of budget consumed)
- **Status**: SLO breached
- **Actions**:
  - **COMPLETE FREEZE** on feature deployments
  - All hands on deck for reliability
  - Post-mortem required
  - Corrective action plan mandatory
  - Executive escalation

### Burn Rate Alerting

We use multi-window, multi-burn-rate alerting as recommended by Google SRE:

#### Critical Alert (Page)
- **Condition**: 10x burn rate over 1 hour AND 10x burn rate over 5 minutes
- **Implication**: Error budget will be exhausted in 3 days
- **Response**: Immediate page, investigate now
- **Query**:
```promql
(
  sum(rate(weather_request_success_total{success="false"}[1h]))
  /
  sum(rate(weather_request_success_total[1h]))
) > (10 * 0.001)  # 10x the 0.1% error budget
AND
(
  sum(rate(weather_request_success_total{success="false"}[5m]))
  /
  sum(rate(weather_request_success_total[5m]))
) > (10 * 0.001)
```

#### Warning Alert (Ticket)
- **Condition**: 3x burn rate over 6 hours AND 3x burn rate over 30 minutes
- **Implication**: Error budget will be exhausted in 10 days
- **Response**: Create ticket, investigate during business hours
- **Query**:
```promql
(
  sum(rate(weather_request_success_total{success="false"}[6h]))
  /
  sum(rate(weather_request_success_total[6h]))
) > (3 * 0.001)
AND
(
  sum(rate(weather_request_success_total{success="false"}[30m]))
  /
  sum(rate(weather_request_success_total[30m]))
) > (3 * 0.001)
```

## SLO Dashboard Queries

### Current Error Budget Remaining

```promql
1 - (
  (
    1 - (
      sum(rate(weather_request_success_total{success="true"}[30d]))
      /
      sum(rate(weather_request_success_total[30d]))
    )
  )
  /
  0.001  # 0.1% error budget
)
```

### Days Until Budget Exhaustion (at current rate)

```promql
(
  (
    0.001  # Error budget
    -
    (
      1 - (
        sum(rate(weather_request_success_total{success="true"}[1h]))
        /
        sum(rate(weather_request_success_total[1h]))
      )
    )
  )
  /
  (
    1 - (
      sum(rate(weather_request_success_total{success="true"}[1h]))
      /
      sum(rate(weather_request_success_total[1h]))
    )
  )
) * 30  # 30 days in measurement window
```

### Request Success Rate (Last 30 Days)

```promql
sum(rate(weather_request_success_total{success="true"}[30d]))
/
sum(rate(weather_request_success_total[30d]))
* 100
```

### P95 Latency Trend

```promql
histogram_quantile(0.95,
  sum(rate(weather_http_request_duration_seconds_bucket[5m])) by (le)
)
```

### P99 Latency Trend

```promql
histogram_quantile(0.99,
  sum(rate(weather_http_request_duration_seconds_bucket[5m])) by (le)
)
```

## Incident Response Procedure

### When SLO is at Risk

1. **Detect**: Alert fires (via PagerDuty/Slack)
2. **Assess**: Check dashboard to confirm scope
3. **Mitigate**: 
   - Check recent deployments (rollback if needed)
   - Check upstream dependencies (OpenWeatherMap API)
   - Check resource utilization (scale if needed)
   - Check error logs for patterns
4. **Communicate**: Update status page, notify stakeholders
5. **Resolve**: Fix root cause
6. **Document**: Create incident report

### Post-Incident Review

After any SLO breach:
1. Schedule blameless post-mortem within 48 hours
2. Document timeline and root cause
3. Identify action items to prevent recurrence
4. Update runbooks
5. Consider SLO adjustment if unrealistic

## SLO Review Schedule

- **Monthly**: Review SLO compliance and error budget consumption
- **Quarterly**: Evaluate if SLOs are appropriate for business needs
- **Annually**: Major SLO review and adjustment

## Dependencies and Assumptions

### Assumptions
- OpenWeatherMap API availability: 99.9%
- Redis cache availability: 99.95%
- AWS ECS platform availability: 99.99%

### Dependency SLOs
- **OpenWeatherMap API**: No formal SLO, but we cache to degrade gracefully
- **Redis**: Cache failures should not cause request failures (failover to API)
- **AWS ECS**: Relies on AWS's 99.99% SLA

### Exclusions
The following are **excluded** from SLO calculations:
- Requests from known malicious IPs (blocked by rate limiter)
- Requests during planned maintenance windows
- Client errors (4xx) due to invalid requests
- Synthetic monitoring probes (tagged separately)

## Monitoring and Alerting Integration

### Grafana Dashboard
- URL: `http://grafana.example.com/d/weather-slo`
- Panels:
  - Error budget burn rate
  - Days until budget exhaustion
  - Current availability %
  - P95/P99 latency trends
  - Request rate
  - Error rate by type

### PagerDuty Integration
- Critical alerts (10x burn rate) → Page on-call SRE
- Warning alerts (3x burn rate) → Create ticket
- Info alerts → Send to Slack only

## References

- [Google SRE Book - Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook - Implementing SLOs](https://sre.google/workbook/implementing-slos/)
- [Prometheus Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)
- [Multi-window, Multi-burn-rate Alerts](https://sre.google/workbook/alerting-on-slos/)
