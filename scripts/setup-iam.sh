#!/bin/bash
set -e

# Weather Alert Service - IAM Setup Script
# This script creates all necessary IAM roles and policies for the project

echo "🔐 Setting up IAM roles for Weather Alert Service"
echo "=================================================="
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

# 1. ECS Task Execution Role
echo "1️⃣  Creating ECS Task Execution Role..."

cat > /tmp/ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name WeatherServiceECSTaskExecutionRole \
  --assume-role-policy-document file:///tmp/ecs-task-execution-trust-policy.json \
  --description "ECS Task Execution Role for Weather Alert Service" \
  --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
  2>/dev/null || echo "Role already exists, continuing..."

# Attach AWS managed policy for ECS task execution
aws iam attach-role-policy \
  --role-name WeatherServiceECSTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Create custom policy for Secrets Manager access
cat > /tmp/secrets-manager-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT_ID}:secret:weather-service/*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name WeatherServiceECSTaskExecutionRole \
  --policy-name SecretsManagerAccess \
  --policy-document file:///tmp/secrets-manager-policy.json

echo "✅ ECS Task Execution Role created"
echo ""

# 2. ECS Task Role (for application runtime)
echo "2️⃣  Creating ECS Task Role..."

cat > /tmp/ecs-task-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name WeatherServiceECSTaskRole \
  --assume-role-policy-document file:///tmp/ecs-task-trust-policy.json \
  --description "ECS Task Role for Weather Alert Service application" \
  --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
  2>/dev/null || echo "Role already exists, continuing..."

# Create custom policy for task role (CloudWatch, X-Ray if needed)
cat > /tmp/task-role-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:us-east-2:${AWS_ACCOUNT_ID}:log-group:/ecs/weather-service:*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name WeatherServiceECSTaskRole \
  --policy-name CloudWatchLogsAccess \
  --policy-document file:///tmp/task-role-policy.json

echo "✅ ECS Task Role created"
echo ""

# 3. GitHub Actions OIDC Role
echo "3️⃣  Creating GitHub Actions OIDC Role..."

# First, check if OIDC provider exists
OIDC_EXISTS=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')]" --output text)

if [ -z "$OIDC_EXISTS" ]; then
  echo "Creating GitHub OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --tags Key=Project,Value=WeatherAlertService
  echo "✅ OIDC provider created"
else
  echo "✅ OIDC provider already exists"
fi

# Create GitHub Actions trust policy
cat > /tmp/github-actions-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
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

aws iam create-role \
  --role-name GitHubActionsWeatherService \
  --assume-role-policy-document file:///tmp/github-actions-trust-policy.json \
  --description "GitHub Actions role for Weather Alert Service CI/CD" \
  --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
  2>/dev/null || echo "Role already exists, continuing..."

# Create custom policy for GitHub Actions
cat > /tmp/github-actions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTasks",
        "ecs:DescribeTaskDefinition",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/WeatherServiceECSTaskExecutionRole",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/WeatherServiceECSTaskRole"
      ]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "arn:aws:logs:us-east-2:${AWS_ACCOUNT_ID}:log-group:/ecs/weather-service:*"
    },
    {
      "Sid": "ELBAccess",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetHealth"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name GitHubActionsWeatherService \
  --policy-name GitHubActionsPolicy \
  --policy-document file:///tmp/github-actions-policy.json

echo "✅ GitHub Actions OIDC Role created"
echo ""

# 4. Terraform Execution Role (if running Terraform from GitHub Actions)
echo "4️⃣  Adding Terraform permissions to GitHub Actions role..."

cat > /tmp/terraform-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::sezzle-weather-terraform-state",
        "arn:aws:s3:::sezzle-weather-terraform-state/*"
      ]
    },
    {
      "Sid": "DynamoDBStateLock",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:us-east-2:${AWS_ACCOUNT_ID}:table/terraform-state-lock"
    },
    {
      "Sid": "TerraformFullAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "elasticache:*",
        "ecs:*",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "logs:*",
        "secretsmanager:*",
        "application-autoscaling:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name GitHubActionsWeatherService \
  --policy-name TerraformExecutionPolicy \
  --policy-document file:///tmp/terraform-policy.json

echo "✅ Terraform permissions added"
echo ""

# Clean up temp files
rm -f /tmp/ecs-task-execution-trust-policy.json
rm -f /tmp/secrets-manager-policy.json
rm -f /tmp/ecs-task-trust-policy.json
rm -f /tmp/task-role-policy.json
rm -f /tmp/github-actions-trust-policy.json
rm -f /tmp/github-actions-policy.json
rm -f /tmp/terraform-policy.json

echo ""
echo "✅ ✅ ✅ IAM Setup Complete! ✅ ✅ ✅"
echo ""
echo "Summary of created roles:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. WeatherServiceECSTaskExecutionRole"
echo "   ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/WeatherServiceECSTaskExecutionRole"
echo "   Purpose: Used by ECS to pull images and start containers"
echo ""
echo "2. WeatherServiceECSTaskRole"
echo "   ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/WeatherServiceECSTaskRole"
echo "   Purpose: Used by the running application"
echo ""
echo "3. GitHubActionsWeatherService"
echo "   ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/GitHubActionsWeatherService"
echo "   Purpose: Used by GitHub Actions for CI/CD"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Add this to your GitHub repository secrets:"
echo "   AWS_ROLE_ARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/GitHubActionsWeatherService"
echo ""
echo "2. Update your Terraform variables with:"
echo "   export TF_VAR_task_execution_role_arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/WeatherServiceECSTaskExecutionRole"
echo "   export TF_VAR_task_role_arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/WeatherServiceECSTaskRole"
echo ""
echo "3. Run: terraform init && terraform plan"
echo ""
