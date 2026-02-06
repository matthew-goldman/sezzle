#!/bin/bash

# Weather Alert Service - AWS Cleanup Script
# This script destroys ALL AWS resources created for the project
# WARNING: This is destructive and cannot be undone!

set -e

echo "☠️  Weather Alert Service - AWS Resource Cleanup"
echo "================================================"
echo ""
echo "⚠️  WARNING: This will DELETE all AWS resources including:"
echo "  - Terraform-managed infrastructure (ECS, ALB, VPC, etc.)"
echo "  - ECR repository and all Docker images"
echo "  - S3 bucket with Terraform state"
echo "  - DynamoDB table for state locking"
echo "  - Secrets Manager secrets"
echo "  - IAM roles and policies"
echo ""
echo "This action CANNOT be undone!"
echo ""

read -p "Are you ABSOLUTELY sure you want to continue? (type 'destroy' to confirm): " CONFIRMATION

if [ "$CONFIRMATION" != "destroy" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
read -p "Last chance! Type 'yes' to proceed: " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="weather-service"
STATE_BUCKET="sezzle-weather-terraform-state"
STATE_LOCK_TABLE="terraform-state-lock"
ECR_REPO="weather-service"

echo ""
echo "🗑️  Starting cleanup in region: $AWS_REGION"
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

# ============================================================================
# 1. Destroy Terraform-managed infrastructure
# ============================================================================
echo "1️⃣  Destroying Terraform-managed infrastructure..."
echo ""

if [ -d "deployments/terraform" ]; then
    cd deployments/terraform
    
    if [ -f "terraform.tfstate" ] || aws s3 ls "s3://${STATE_BUCKET}/weather-service/terraform.tfstate" 2>/dev/null; then
        echo "Running terraform destroy..."
        
        # Initialize terraform if needed
        terraform init -reconfigure || true
        
        # Destroy with auto-approve
        terraform destroy -auto-approve || {
            echo "⚠️  Terraform destroy failed. Continuing with manual cleanup..."
        }
    else
        echo "No Terraform state found, skipping terraform destroy"
    fi
    
    cd ../..
else
    echo "No Terraform directory found, skipping"
fi

echo "✅ Terraform resources destroyed (or skipped)"
echo ""

# ============================================================================
# 2. Delete ECR Repository
# ============================================================================
echo "2️⃣  Deleting ECR repository..."

if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
    echo "Deleting ECR repository and all images..."
    aws ecr delete-repository \
        --repository-name "$ECR_REPO" \
        --region "$AWS_REGION" \
        --force 2>/dev/null || echo "Failed to delete ECR repository"
    echo "✅ ECR repository deleted"
else
    echo "ECR repository not found, skipping"
fi
echo ""

# ============================================================================
# 3. Delete Secrets Manager Secrets
# ============================================================================
echo "3️⃣  Deleting Secrets Manager secrets..."

SECRET_NAME="${PROJECT_NAME}/openweather-api-key"

if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
    echo "Deleting secret: $SECRET_NAME"
    aws secretsmanager delete-secret \
        --secret-id "$SECRET_NAME" \
        --region "$AWS_REGION" \
        --force-delete-without-recovery 2>/dev/null || echo "Failed to delete secret"
    echo "✅ Secret deleted"
else
    echo "Secret not found, skipping"
fi
echo ""

# ============================================================================
# 4. Delete CloudWatch Log Groups
# ============================================================================
echo "4️⃣  Deleting CloudWatch log groups..."

LOG_GROUP="/ecs/${PROJECT_NAME}"

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$AWS_REGION" 2>/dev/null | grep -q "$LOG_GROUP"; then
    echo "Deleting log group: $LOG_GROUP"
    aws logs delete-log-group \
        --log-group-name "$LOG_GROUP" \
        --region "$AWS_REGION" 2>/dev/null || echo "Failed to delete log group"
    echo "✅ Log group deleted"
else
    echo "Log group not found, skipping"
fi
echo ""

# ============================================================================
# 5. Delete IAM Roles
# ============================================================================
echo "5️⃣  Deleting IAM roles..."

delete_iam_role() {
    local ROLE_NAME=$1
    
    if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null >/dev/null; then
        echo "Deleting IAM role: $ROLE_NAME"
        
        # Detach all managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
        for POLICY_ARN in $ATTACHED_POLICIES; do
            echo "  Detaching policy: $POLICY_ARN"
            aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
        done
        
        # Delete all inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text)
        for POLICY_NAME in $INLINE_POLICIES; do
            echo "  Deleting inline policy: $POLICY_NAME"
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" 2>/dev/null || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || echo "  Failed to delete role"
        echo "  ✅ Role deleted"
    else
        echo "Role $ROLE_NAME not found, skipping"
    fi
}

delete_iam_role "WeatherServiceECSTaskExecutionRole"
delete_iam_role "WeatherServiceECSTaskRole"
delete_iam_role "GitHubActionsWeatherService"

echo ""

# ============================================================================
# 6. Delete OIDC Provider
# ============================================================================
echo "6️⃣  Deleting GitHub OIDC provider..."

OIDC_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" --output text)

if [ -n "$OIDC_ARN" ]; then
    echo "Deleting OIDC provider: $OIDC_ARN"
    aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null || echo "Failed to delete OIDC provider"
    echo "✅ OIDC provider deleted"
else
    echo "OIDC provider not found, skipping"
fi
echo ""

# ============================================================================
# 7. Empty and Delete S3 Bucket
# ============================================================================
echo "7️⃣  Emptying and deleting S3 bucket..."

if aws s3 ls "s3://${STATE_BUCKET}" 2>/dev/null; then
    echo "Emptying S3 bucket: $STATE_BUCKET"
    aws s3 rm "s3://${STATE_BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null || true
    
    # Delete all versions (if versioning was enabled)
    echo "Deleting all object versions..."
    aws s3api list-object-versions \
        --bucket "$STATE_BUCKET" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null | \
    jq -r '.Versions[]? | "--key \"" + .Key + "\" --version-id \"" + .VersionId + "\""' | \
    xargs -I {} aws s3api delete-object --bucket "$STATE_BUCKET" --region "$AWS_REGION" {} 2>/dev/null || true
    
    # Delete all delete markers
    aws s3api list-object-versions \
        --bucket "$STATE_BUCKET" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null | \
    jq -r '.DeleteMarkers[]? | "--key \"" + .Key + "\" --version-id \"" + .VersionId + "\""' | \
    xargs -I {} aws s3api delete-object --bucket "$STATE_BUCKET" --region "$AWS_REGION" {} 2>/dev/null || true
    
    echo "Deleting S3 bucket..."
    aws s3api delete-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" 2>/dev/null || echo "Failed to delete S3 bucket"
    echo "✅ S3 bucket deleted"
else
    echo "S3 bucket not found, skipping"
fi
echo ""

# ============================================================================
# 8. Delete DynamoDB Table
# ============================================================================
echo "8️⃣  Deleting DynamoDB table..."

if aws dynamodb describe-table --table-name "$STATE_LOCK_TABLE" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
    echo "Deleting DynamoDB table: $STATE_LOCK_TABLE"
    aws dynamodb delete-table --table-name "$STATE_LOCK_TABLE" --region "$AWS_REGION" 2>/dev/null || echo "Failed to delete DynamoDB table"
    echo "✅ DynamoDB table deleted"
else
    echo "DynamoDB table not found, skipping"
fi
echo ""

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "✅ ✅ ✅ Cleanup Complete! ✅ ✅ ✅"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The following resources have been deleted:"
echo "  ✅ Terraform infrastructure (ECS, VPC, ALB, ElastiCache, etc.)"
echo "  ✅ ECR repository: $ECR_REPO"
echo "  ✅ Secrets Manager secret: $SECRET_NAME"
echo "  ✅ CloudWatch log group: $LOG_GROUP"
echo "  ✅ IAM roles: WeatherServiceECSTaskExecutionRole, WeatherServiceECSTaskRole, GitHubActionsWeatherService"
echo "  ✅ GitHub OIDC provider"
echo "  ✅ S3 bucket: $STATE_BUCKET"
echo "  ✅ DynamoDB table: $STATE_LOCK_TABLE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  Note: Some resources may take a few minutes to fully delete."
echo "⚠️  Check the AWS Console to verify all resources are gone."
echo ""
echo "To verify cleanup:"
echo "  aws ecs list-clusters --region $AWS_REGION"
echo "  aws ecr describe-repositories --region $AWS_REGION"
echo "  aws s3 ls"
echo "  aws iam list-roles | grep Weather"
echo ""
