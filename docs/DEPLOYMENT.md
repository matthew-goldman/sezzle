# Quick Deployment Guide

This guide will help you deploy the Weather Alert Service to AWS and set up the complete infrastructure.

## Prerequisites Checklist

- [ ] AWS account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] Terraform installed (v1.5+)
- [ ] Docker installed
- [ ] Git installed
- [ ] OpenWeatherMap API key ([get free key](https://openweathermap.org/api))
- [ ] GitHub repository created (https://github.com/matthew-goldman/sezzle)

## 🚀 Step-by-Step Deployment

### Step 1: Clone and Setup (5 minutes)

```bash
# Clone repository
git clone https://github.com/matthew-goldman/sezzle.git
cd sezzle

# Run setup script
chmod +x scripts/setup.sh
./scripts/setup.sh

# Enter your OpenWeatherMap API key when prompted
```

### Step 2: AWS Infrastructure Setup (10 minutes)

```bash
# Set AWS region
export AWS_REGION=us-east-2

# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket sezzle-weather-terraform-state \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket sezzle-weather-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-2

# Create ECR repository
aws ecr create-repository \
  --repository-name weather-service \
  --region us-east-2

# Store API key in Secrets Manager
aws secretsmanager create-secret \
  --name weather-service/openweather-api-key \
  --description "OpenWeatherMap API key for Weather Alert Service" \
  --secret-string "YOUR_OPENWEATHER_API_KEY" \
  --region us-east-2
```

### Step 3: Build and Push Docker Image (5 minutes)

```bash
# Get ECR login credentials
aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-2.amazonaws.com

# Build Docker image
docker build -t weather-service:latest .

# Tag for ECR
ECR_URI=$(aws ecr describe-repositories --repository-names weather-service --region us-east-2 --query 'repositories[0].repositoryUri' --output text)
docker tag weather-service:latest $ECR_URI:latest

# Push to ECR
docker push $ECR_URI:latest
```

### Step 4: Deploy Infrastructure with Terraform (15 minutes)

```bash
cd deployments/terraform

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
  -var="ecr_repository_url=$ECR_URI" \
  -var="environment=prod"

# Apply infrastructure
terraform apply \
  -var="ecr_repository_url=$ECR_URI" \
  -var="environment=prod"

# Save outputs
terraform output > outputs.txt
```

### Step 5: Update API Key Secret (2 minutes)

```bash
# Update the secret value with your actual API key
aws secretsmanager update-secret \
  --secret-id $(terraform output -raw secrets_manager_secret_arn) \
  --secret-string "YOUR_ACTUAL_API_KEY" \
  --region us-east-2
```

### Step 6: Verify Deployment (5 minutes)

```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_url)

# Test health endpoint
curl $ALB_URL/health

# Test weather endpoint
curl "$ALB_URL/weather/London"

# View metrics
curl "$ALB_URL/metrics"
```

### Step 7: Setup GitHub Actions (10 minutes)

1. **Create OIDC Provider in AWS**:

```bash
# Create OIDC provider for GitHub Actions
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

2. **Create IAM Role for GitHub Actions**:

```bash
cat > github-actions-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:matthew-goldman/sezzle:*"
        }
      }
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name GitHubActionsWeatherService \
  --assume-role-policy-document file://github-actions-trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name GitHubActionsWeatherService \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

aws iam attach-role-policy \
  --role-name GitHubActionsWeatherService \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
```

3. **Add GitHub Secrets**:

Go to your repository settings and add:
- `AWS_ROLE_ARN`: `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsWeatherService`

### Step 8: Setup Monitoring (Optional - 15 minutes)

If you want to run Prometheus/Grafana locally:

```bash
cd ../..  # Back to root directory

# Start monitoring stack
docker-compose up -d prometheus grafana

# Access Grafana
open http://localhost:3000
# Login: admin/admin

# Import dashboard from docs/grafana/dashboard.json
```

## 📊 Accessing Your Service

After successful deployment:

- **Service URL**: `http://YOUR_ALB_DNS_NAME`
- **Health Check**: `http://YOUR_ALB_DNS_NAME/health`
- **Weather API**: `http://YOUR_ALB_DNS_NAME/weather/{location}`
- **Metrics**: `http://YOUR_ALB_DNS_NAME/metrics`

## 🔍 Monitoring and Logs

```bash
# View ECS service status
aws ecs describe-services \
  --cluster weather-service-cluster \
  --services weather-service

# View CloudWatch logs
aws logs tail /ecs/weather-service --follow

# View recent deployments
aws ecs list-tasks \
  --cluster weather-service-cluster \
  --service-name weather-service
```

## 🧪 Testing the Service

```bash
# Get ALB URL
ALB_URL=$(cd deployments/terraform && terraform output -raw alb_url)

# Health check
curl -s $ALB_URL/health | jq

# Get weather for different locations
curl -s "$ALB_URL/weather/London" | jq
curl -s "$ALB_URL/weather/Tokyo" | jq
curl -s "$ALB_URL/weather/New%20York" | jq

# Check metrics
curl -s $ALB_URL/metrics | grep weather_

# Load test (requires hey or similar)
hey -n 1000 -c 10 "$ALB_URL/weather/Seattle"
```

## 🔧 Troubleshooting

### Service Not Starting

```bash
# Check ECS task logs
aws ecs describe-tasks \
  --cluster weather-service-cluster \
  --tasks $(aws ecs list-tasks --cluster weather-service-cluster --service-name weather-service --query 'taskArns[0]' --output text)

# Check CloudWatch logs for errors
aws logs filter-log-events \
  --log-group-name /ecs/weather-service \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '30 minutes ago' +%s)000
```

### Can't Access Service

```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=weather-service-*"
```

### API Key Issues

```bash
# Verify secret exists
aws secretsmanager describe-secret \
  --secret-id weather-service/openweather-api-key

# Update secret
aws secretsmanager update-secret \
  --secret-id weather-service/openweather-api-key \
  --secret-string "NEW_API_KEY"

# Force new deployment to pick up secret
aws ecs update-service \
  --cluster weather-service-cluster \
  --service weather-service \
  --force-new-deployment
```

## 💰 Cost Estimation

Expected monthly costs (us-east-2):

| Service | Usage | Cost |
|---------|-------|------|
| ECS Fargate | 2 tasks, 0.25 vCPU, 0.5 GB | ~$15 |
| ALB | 1 ALB | ~$16 |
| ElastiCache (Redis) | t3.micro | ~$12 |
| CloudWatch Logs | ~5 GB/month | ~$3 |
| Data Transfer | ~10 GB/month | ~$1 |
| **Total** | | **~$47/month** |

To reduce costs for dev environment:
- Use single Fargate task
- Use in-memory cache instead of Redis
- Reduce log retention

## 🧹 Cleanup

To destroy all resources and avoid charges:

```bash
cd deployments/terraform

# Destroy infrastructure
terraform destroy -auto-approve

# Delete ECR repository
aws ecr delete-repository \
  --repository-name weather-service \
  --force \
  --region us-east-2

# Delete S3 state bucket
aws s3 rb s3://sezzle-weather-terraform-state --force

# Delete DynamoDB table
aws dynamodb delete-table \
  --table-name terraform-state-lock \
  --region us-east-2

# Delete Secrets Manager secret
aws secretsmanager delete-secret \
  --secret-id weather-service/openweather-api-key \
  --force-delete-without-recovery \
  --region us-east-2
```

## 📚 Next Steps

1. **Setup Monitoring**: Configure Prometheus/Grafana
2. **Setup Alerts**: Configure PagerDuty integration
3. **Setup CI/CD**: Push code to GitHub to trigger deployments
4. **Review SLOs**: See `docs/SLO.md` for SLO definitions
5. **Read Runbooks**: Familiarize yourself with incident response procedures

## 🆘 Getting Help

- Check README.md for comprehensive documentation
- Review CLAUDE.md for development guidelines
- Check docs/runbooks/ for operational procedures
- Review CloudWatch logs for errors
- Check Prometheus metrics for performance issues

## ✅ Success Criteria

Your deployment is successful when:

- [ ] Health endpoint returns 200 OK
- [ ] Weather endpoint returns valid data
- [ ] Metrics endpoint exposes Prometheus metrics
- [ ] ECS service shows 2 running tasks
- [ ] CloudWatch logs show no errors
- [ ] Load test shows <500ms P95 latency

Congratulations! Your Weather Alert Service is now running in production! 🎉
