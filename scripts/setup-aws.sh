#!/bin/bash

# Weather Alert Service - Complete AWS Setup Script
# This script creates all necessary AWS resources before running Terraform

echo "☁️  Weather Alert Service - AWS Initial Setup"
echo "=============================================="
echo ""
echo "This script will create:"
echo "  1. S3 bucket for Terraform state"
echo "  2. DynamoDB table for state locking"
echo "  3. ECR repository for Docker images"
echo "  4. Secrets Manager secret for API key"
echo "  5. IAM roles for ECS and GitHub Actions"
echo ""

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="weather-service"
STATE_BUCKET="sezzle-weather-terraform-state"
STATE_LOCK_TABLE="terraform-state-lock"
ECR_REPO="weather-service"

echo "Configuration:"
echo "  AWS Region: $AWS_REGION"
echo "  State Bucket: $STATE_BUCKET"
echo "  ECR Repository: $ECR_REPO"
echo ""

read -p "Continue with setup? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

# Get AWS account ID
echo ""
echo "🔍 Getting AWS account information..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

# ============================================================================
# 1. S3 Bucket for Terraform State
# ============================================================================
echo "📦 Step 1/5: Creating S3 bucket for Terraform state..."

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
    echo "✅ S3 bucket '$STATE_BUCKET' already exists"
else
    echo "Creating S3 bucket..."
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        # us-east-1 doesn't need LocationConstraint
        aws s3api create-bucket \
            --bucket "$STATE_BUCKET" \
            --region "$AWS_REGION" >/dev/null
    else
        aws s3api create-bucket \
            --bucket "$STATE_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
    fi
    
    echo "✅ S3 bucket created"
fi

# Enable versioning
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --versioning-configuration Status=Enabled 2>/dev/null || echo "  (already configured)"

# Enable encryption
echo "Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket "$STATE_BUCKET" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }' 2>/dev/null || echo "  (already configured)"

# Block public access
echo "Blocking public access..."
aws s3api put-public-access-block \
    --bucket "$STATE_BUCKET" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" 2>/dev/null || echo "  (already configured)"

# Add lifecycle policy to clean up old versions
echo "Setting lifecycle policy..."
aws s3api put-bucket-lifecycle-configuration \
    --bucket "$STATE_BUCKET" \
    --lifecycle-configuration '{
        "Rules": [{
            "Id": "DeleteOldVersions",
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 90
            }
        }]
    }' 2>/dev/null || echo "  (already configured)"

echo "✅ S3 bucket configured with versioning, encryption, and lifecycle policy"
echo ""

# ============================================================================
# 2. DynamoDB Table for State Locking
# ============================================================================
echo "🔒 Step 2/5: Creating DynamoDB table for state locking..."

if aws dynamodb describe-table --table-name "$STATE_LOCK_TABLE" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
    echo "✅ DynamoDB table '$STATE_LOCK_TABLE' already exists"
else
    echo "Creating DynamoDB table..."
    aws dynamodb create-table \
        --table-name "$STATE_LOCK_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script
    
    echo "Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "$STATE_LOCK_TABLE" --region "$AWS_REGION"
    
    echo "✅ DynamoDB table created"
fi
echo ""

# ============================================================================
# 3. ECR Repository
# ============================================================================
echo "🐳 Step 3/5: Creating ECR repository..."

if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
    echo "✅ ECR repository '$ECR_REPO' already exists"
else
    echo "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name "$ECR_REPO" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
        >/dev/null
    
    echo "✅ ECR repository created"
fi

# Set lifecycle policy to clean up old images
echo "Setting ECR lifecycle policy..."
aws ecr put-lifecycle-policy \
    --repository-name "$ECR_REPO" \
    --region "$AWS_REGION" \
    --lifecycle-policy-text '{
        "rules": [{
            "rulePriority": 1,
            "description": "Keep last 10 images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        }]
    }' >/dev/null

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
echo "✅ ECR repository configured"
echo "   URI: $ECR_URI"
echo ""

# ============================================================================
# 4. Secrets Manager Secret
# ============================================================================
echo "🔐 Step 4/5: Creating Secrets Manager secret..."

SECRET_NAME="${PROJECT_NAME}/openweather-api-key"

if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
    echo "✅ Secret '$SECRET_NAME' already exists"
    echo ""
    read -p "Do you want to update the API key? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your OpenWeatherMap API key: " API_KEY
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string "$API_KEY" \
            --region "$AWS_REGION" >/dev/null
        echo "✅ Secret updated"
    fi
else
    echo "Creating Secrets Manager secret..."
    echo ""
    
    # Check if environment variable is set
    if [ -n "$OPENWEATHER_API_KEY" ]; then
        echo "Found OPENWEATHER_API_KEY environment variable"
        API_KEY="$OPENWEATHER_API_KEY"
        echo "✅ Using API key from environment"
    else
        echo "You need an OpenWeatherMap API key."
        echo "Get one free at: https://openweathermap.org/api"
        echo "Note: New keys take 10-15 minutes to activate"
        echo ""
        read -p "Enter your OpenWeatherMap API key (or press Enter to skip): " API_KEY
    fi
    
    if [ -z "$API_KEY" ]; then
        API_KEY="PLACEHOLDER_REPLACE_ME"
        echo "⚠️  Using placeholder - you MUST update this later!"
    fi
    
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "OpenWeatherMap API key for Weather Alert Service" \
        --secret-string "$API_KEY" \
        --region "$AWS_REGION" \
        --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script >/dev/null
    
    echo "✅ Secret created"
    
    if [ "$API_KEY" = "PLACEHOLDER_REPLACE_ME" ]; then
        echo ""
        echo "⚠️  IMPORTANT: Update the secret later with:"
        echo "   aws secretsmanager update-secret \\"
        echo "     --secret-id $SECRET_NAME \\"
        echo "     --secret-string YOUR_ACTUAL_API_KEY \\"
        echo "     --region $AWS_REGION"
    fi
fi
echo ""

# ============================================================================
# 5. IAM Roles
# ============================================================================
echo "👤 Step 5/5: Creating IAM roles and service-linked roles..."
echo ""

# 5a. Create Service-Linked Roles first
echo "Creating AWS Service-Linked Roles..."

echo "  - ElastiCache service-linked role..."
aws iam create-service-linked-role \
  --aws-service-name elasticache.amazonaws.com \
  2>/dev/null && echo "    ✅ Created" || echo "    ✅ Already exists"

echo "  - ECS service-linked role..."
aws iam create-service-linked-role \
  --aws-service-name ecs.amazonaws.com \
  2>/dev/null && echo "    ✅ Created" || echo "    ✅ Already exists"

echo "  - Application Auto Scaling service-linked role..."
aws iam create-service-linked-role \
  --aws-service-name ecs.application-autoscaling.amazonaws.com \
  2>/dev/null && echo "    ✅ Created" || echo "    ✅ Already exists"

echo ""

# 5b. ECS Task Execution Role
# 5b. ECS Task Execution Role
echo "Creating ECS Task Execution Role..."

cat > /tmp/ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name WeatherServiceECSTaskExecutionRole \
  --assume-role-policy-document file:///tmp/ecs-task-execution-trust-policy.json \
  --description "ECS Task Execution Role for Weather Alert Service" \
  --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
  2>/dev/null || echo "Role already exists, continuing..."

aws iam attach-role-policy \
  --role-name WeatherServiceECSTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || true

cat > /tmp/secrets-manager-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ],
    "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name WeatherServiceECSTaskExecutionRole \
  --policy-name SecretsManagerAccess \
  --policy-document file:///tmp/secrets-manager-policy.json

echo "✅ ECS Task Execution Role created"

# 5b. ECS Task Role
# 5c. ECS Task Role
echo "Creating ECS Task Role..."

aws iam create-role \
  --role-name WeatherServiceECSTaskRole \
  --assume-role-policy-document file:///tmp/ecs-task-execution-trust-policy.json \
  --description "ECS Task Role for Weather Alert Service application" \
  --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
  2>/dev/null || echo "Role already exists, continuing..."

cat > /tmp/task-role-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ],
    "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/ecs/${PROJECT_NAME}:*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name WeatherServiceECSTaskRole \
  --policy-name CloudWatchLogsAccess \
  --policy-document file:///tmp/task-role-policy.json

echo "✅ ECS Task Role created"

# 5c. GitHub Actions OIDC Role
# 5d. GitHub Actions OIDC Role
echo "Creating GitHub Actions OIDC role..."

# Check if OIDC provider exists
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

cat > /tmp/github-actions-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
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
  }]
}
EOF

aws iam create-role \
  --role-name GitHubActionsWeatherService \
  --assume-role-policy-document file:///tmp/github-actions-trust-policy.json \
  --description "GitHub Actions role for Weather Alert Service CI/CD" \
  --tags Key=Project,Value=WeatherAlertService Key=ManagedBy,Value=Script \
  2>/dev/null || echo "Role already exists, continuing..."

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
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories"
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
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/ecs/${PROJECT_NAME}:*"
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
    },
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
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/*"
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
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${STATE_LOCK_TABLE}"
    },
    {
      "Sid": "TerraformResourceAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "elasticache:*",
        "ecs:*",
        "iam:GetRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:CreateServiceLinkedRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "logs:*",
        "secretsmanager:*",
        "application-autoscaling:*",
        "route53:*",
        "acm:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name GitHubActionsWeatherService \
  --policy-name GitHubActionsFullPolicy \
  --policy-document file:///tmp/github-actions-policy.json

echo "✅ GitHub Actions Role created"

# Clean up temp files
rm -f /tmp/ecs-task-execution-trust-policy.json
rm -f /tmp/secrets-manager-policy.json
rm -f /tmp/task-role-policy.json
rm -f /tmp/github-actions-trust-policy.json
rm -f /tmp/github-actions-policy.json

echo ""
echo "✅ ✅ ✅ AWS Setup Complete! ✅ ✅ ✅"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Setup Summary:"
echo ""
echo "S3 Terraform State:"
echo "  Bucket: $STATE_BUCKET"
echo "  Region: $AWS_REGION"
echo ""
echo "DynamoDB State Lock:"
echo "  Table: $STATE_LOCK_TABLE"
echo ""
echo "ECR Repository:"
echo "  Name: $ECR_REPO"
echo "  URI: $ECR_URI"
echo ""
echo "Secrets Manager:"
echo "  Secret: $SECRET_NAME"
echo ""
echo "IAM Roles:"
echo "  - WeatherServiceECSTaskExecutionRole"
echo "  - WeatherServiceECSTaskRole"
echo "  - GitHubActionsWeatherService"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Add GitHub Secret:"
echo "   Go to: https://github.com/matthew-goldman/sezzle/settings/secrets/actions"
echo "   Add secret:"
echo "     Name: AWS_ROLE_ARN"
echo "     Value: arn:aws:iam::${AWS_ACCOUNT_ID}:role/GitHubActionsWeatherService"
echo ""
echo "2. Create terraform.tfvars:"
echo "   cd deployments/terraform"
echo "   cat > terraform.tfvars <<EOF"
echo "   ecr_repository_url = \"$ECR_URI\""
echo "   environment        = \"prod\""
echo "   EOF"
echo ""
echo "3. Initialize and apply Terraform:"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "4. Build and push Docker image:"
echo "   aws ecr get-login-password --region $AWS_REGION | \\"
echo "     docker login --username AWS --password-stdin $ECR_URI"
echo "   docker build -t $ECR_REPO:latest ."
echo "   docker tag $ECR_REPO:latest $ECR_URI:latest"
echo "   docker push $ECR_URI:latest"
echo ""
echo "5. Push to GitHub to trigger CI/CD:"
echo "   git add ."
echo "   git commit -m \"Add initial setup\""
echo "   git push origin main"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""