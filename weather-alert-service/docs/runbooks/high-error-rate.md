# Runbook: High Error Rate

## Alert

**Alert Name**: `HighErrorBudgetBurnRate`

**Severity**: Critical

**Description**: Error rate exceeds threshold, rapidly consuming error budget.

## Symptoms

- PagerDuty page triggered
- Grafana dashboard shows elevated error rate
- Users may be experiencing service degradation
- Error budget burn rate > 10x normal

## Impact

- **User Impact**: Users receiving errors when querying weather data
- **SLO Impact**: Consuming error budget at 10x rate (budget exhausted in ~3 days)
- **Business Impact**: Potential reputation damage, user churn

## Possible Causes

1. **Upstream API Issues**
   - OpenWeatherMap API is down or degraded
   - Rate limiting from upstream
   - API key issues (expired, invalid, quota exceeded)

2. **Infrastructure Issues**
   - ECS tasks crashing/restarting
   - AWS region issues
   - Load balancer misconfiguration
   - Network connectivity problems

3. **Application Issues**
   - Recent deployment introduced bugs
   - Memory leaks causing crashes
   - Database/cache connectivity issues
   - Timeout misconfigurations

4. **Dependency Issues**
   - Redis cache unavailable
   - DNS resolution failures
   - Certificate expiration

## Investigation Steps

### Step 1: Assess Scope (2 minutes)

1. **Check current error rate**:
```bash
# In Prometheus/Grafana
sum(rate(weather_request_success_total{success="false"}[5m])) 
/ 
sum(rate(weather_request_success_total[5m]))
```

2. **Check affected endpoints**:
```bash
sum(rate(weather_http_requests_total{status=~"5.."}[5m])) by (endpoint)
```

3. **Check error distribution**:
```bash
sum(rate(weather_http_requests_total[5m])) by (status)
```

### Step 2: Check Recent Changes (2 minutes)

1. **Check recent deployments**:
```bash
# In GitHub
git log --oneline -10

# In AWS ECS
aws ecs describe-services \
  --cluster weather-service-cluster \
  --services weather-service \
  --query 'services[0].deployments'
```

2. **If recent deployment, consider rollback**:
```bash
# Rollback to previous task definition
aws ecs update-service \
  --cluster weather-service-cluster \
  --service weather-service \
  --task-definition weather-service:PREVIOUS_VERSION
```

### Step 3: Check Upstream Dependencies (3 minutes)

1. **Check OpenWeatherMap API status**:
```bash
# Test direct API call
curl "https://api.openweathermap.org/data/2.5/weather?q=London&appid=YOUR_KEY"

# Check upstream error rate
sum(rate(weather_api_requests_total{status="error"}[5m]))
```

2. **Check API quota**:
   - Visit OpenWeatherMap dashboard
   - Verify API key is valid and has remaining quota

3. **If upstream is down**:
   - Verify cache is serving stale data
   - Consider increasing cache TTL temporarily
   - Post status update for users

### Step 4: Check Infrastructure (3 minutes)

1. **Check ECS task health**:
```bash
# List tasks
aws ecs list-tasks \
  --cluster weather-service-cluster \
  --service-name weather-service

# Describe tasks
aws ecs describe-tasks \
  --cluster weather-service-cluster \
  --tasks <task-ids>
```

2. **Check CloudWatch logs**:
```bash
# Recent errors
aws logs filter-log-events \
  --log-group-name /ecs/weather-service \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '10 minutes ago' +%s)000
```

3. **Check resource utilization**:
```bash
# CPU/Memory metrics in CloudWatch
avg(rate(container_cpu_usage_seconds_total[5m])) by (container_name)
avg(container_memory_usage_bytes) by (container_name)
```

### Step 5: Check Application Logs (5 minutes)

1. **Look for error patterns**:
```bash
# Most common errors
aws logs filter-log-events \
  --log-group-name /ecs/weather-service \
  --filter-pattern "level=error" \
  --start-time $(date -u -d '30 minutes ago' +%s)000 \
| jq '.events[].message' \
| sort | uniq -c | sort -rn | head -20
```

2. **Check for specific error types**:
   - Timeout errors
   - Connection refused
   - Cache errors
   - Panic/crash logs

### Step 6: Check Cache Health (2 minutes)

1. **Verify Redis connectivity**:
```bash
# From ECS task
aws ecs execute-command \
  --cluster weather-service-cluster \
  --task <task-id> \
  --container weather-service \
  --interactive \
  --command "redis-cli -h $REDIS_ADDR ping"
```

2. **Check cache metrics**:
```bash
rate(weather_cache_errors_total[5m])
rate(weather_cache_hits_total[5m]) / (rate(weather_cache_hits_total[5m]) + rate(weather_cache_misses_total[5m]))
```

## Mitigation Steps

### Quick Fixes (Do First)

1. **If recent deployment is cause**:
```bash
# Rollback immediately
aws ecs update-service \
  --cluster weather-service-cluster \
  --service weather-service \
  --task-definition weather-service:$(($CURRENT_VERSION - 1))

# Wait for rollback
aws ecs wait services-stable \
  --cluster weather-service-cluster \
  --services weather-service
```

2. **If upstream API is down**:
```bash
# Increase cache TTL via environment variable
# Deploy new task definition with CACHE_TTL=30m
# This serves stale data but keeps service available
```

3. **If quota exceeded**:
   - Upgrade OpenWeatherMap plan
   - Temporarily increase cache TTL
   - Enable aggressive rate limiting

4. **If infrastructure issue**:
```bash
# Scale up to replace unhealthy tasks
aws ecs update-service \
  --cluster weather-service-cluster \
  --service weather-service \
  --desired-count $((CURRENT_COUNT + 2))
```

### Longer-term Fixes (Do After)

1. **Fix root cause** identified in investigation
2. **Deploy fix** via normal CI/CD process
3. **Monitor** error rate for 30 minutes
4. **Document** in incident report

## Escalation

### When to Escalate

- Error rate not improving after 15 minutes
- Root cause unclear after investigation
- Multiple services affected
- Customer-facing impact severe

### Who to Escalate To

1. **First**: Senior SRE on-call (PagerDuty escalation policy)
2. **Second**: Engineering manager
3. **Third**: VP of Engineering (if customer impact severe)

### Escalation Template

```
INCIDENT: High error rate on Weather Alert Service
SEVERITY: Critical
DURATION: X minutes
ERROR RATE: X%
IMPACT: X% of requests failing
INVESTIGATION: [Summary of findings]
MITIGATION ATTEMPTED: [What you've tried]
NEED: [What you need help with]
```

## Communication

### Status Page Update

```
[INVESTIGATING] Weather Alert Service - Elevated Error Rate

We are currently investigating elevated error rates affecting 
the Weather Alert Service. Some requests may fail or timeout.
We are working to resolve this as quickly as possible.

Last update: [timestamp]
```

### Resolution Update

```
[RESOLVED] Weather Alert Service - Elevated Error Rate

The issue causing elevated error rates has been identified and 
resolved. Service has returned to normal operation.

Root cause: [brief description]
Resolution: [brief description]

Last update: [timestamp]
```

## Post-Incident Tasks

1. **Create incident ticket** in Jira/GitHub Issues
2. **Schedule blameless post-mortem** within 48 hours
3. **Write incident report** including:
   - Timeline
   - Root cause
   - Impact quantification
   - Action items
4. **Update runbook** if investigation process can be improved
5. **Update alerts** if false positive or missed signals
6. **Track action items** to completion

## Prevention

- Monitor error budget consumption weekly
- Review deployment practices (gradual rollout, canary deployments)
- Implement circuit breakers for upstream dependencies
- Set up synthetic monitoring to catch issues before users
- Regular chaos engineering exercises
- Maintain up-to-date runbooks

## Related Runbooks

- [High Latency](high-latency.md)
- [Upstream API Issues](upstream-api-issues.md)
- [Cache Failures](cache-failures.md)
- [Service Down](service-down.md)

## Metrics Reference

```promql
# Current error rate
sum(rate(weather_request_success_total{success="false"}[5m])) 
/ 
sum(rate(weather_request_success_total[5m]))

# Error budget burn rate
(error_rate / error_budget) * 100

# Requests per second
sum(rate(weather_http_requests_total[5m]))

# Upstream API errors
sum(rate(weather_api_requests_total{status="error"}[5m]))

# Cache hit rate
sum(rate(weather_cache_hits_total[5m])) 
/ 
(sum(rate(weather_cache_hits_total[5m])) + sum(rate(weather_cache_misses_total[5m])))
```

## Tools and Dashboards

- **Grafana**: http://grafana.example.com/d/weather-service
- **Prometheus**: http://prometheus.example.com
- **AWS Console**: https://console.aws.amazon.com/ecs/
- **CloudWatch Logs**: https://console.aws.amazon.com/cloudwatch/
- **PagerDuty**: https://sezzle.pagerduty.com

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-02-06 | Matthew Goldman | Initial version |
