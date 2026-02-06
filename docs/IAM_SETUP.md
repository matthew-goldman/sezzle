# IAM Setup Guide - AWS Console Instructions

If you prefer to set up IAM roles through the AWS Console, follow these steps.

## Overview

You need to create 3 IAM roles:
1. **ECS Task Execution Role** - For ECS to pull images and start containers
2. **ECS Task Role** - For the running application
3. **GitHub Actions Role** - For CI/CD pipeline

---

## Role 1: ECS Task Execution Role

### Step 1: Create the Role

1. Go to **IAM Console** → **Roles** → **Create role**
2. Select **AWS service** as trusted entity type
3. Choose **Elastic Container Service** from the service list
4. Choose **Elastic Container Service Task** use case
5. Click **Next**

### Step 2: Attach Policies

1. Search for and select: `AmazonECSTaskExecutionRolePolicy` (AWS managed policy)
2. Click **Next**

### Step 3: Name and Create

1. Role name: `WeatherServiceECSTaskExecutionRole`
2. Description: `ECS Task Execution Role for Weather Alert Service`
3. Add tags:
   - Key: `Project`, Value: `WeatherAlertService`
   - Key: `ManagedBy`, Value: `Manual`
4. Click **Create role**

### Step 4: Add Secrets Manager Policy

1. Find the role you just created
2. Click **Add permissions** → **Create inline policy**
3. Click **JSON** tab and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-2:YOUR_ACCOUNT_ID:secret:weather-service/*"
    }
  ]
}
```

4. Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID
5. Policy name: `SecretsManagerAccess`
6. Click **Create policy**

**✅ Role 1 Complete!** Copy the Role ARN - you'll need it for Terraform.

---

## Role 2: ECS Task Role

### Step 1: Create the Role

1. Go to **IAM Console** → **Roles** → **Create role**
2. Select **AWS service** as trusted entity type
3. Choose **Elastic Container Service**
4. Choose **Elastic Container Service Task** use case
5. Click **Next**

### Step 2: Skip Managed Policies

1. Don't select any managed policies
2. Click **Next**

### Step 3: Name and Create

1. Role name: `WeatherServiceECSTaskRole`
2. Description: `ECS Task Role for Weather Alert Service application`
3. Add tags:
   - Key: `Project`, Value: `WeatherAlertService`
   - Key: `ManagedBy`, Value: `Manual`
4. Click **Create role**

### Step 4: Add CloudWatch Logs Policy

1. Find the role you just created
2. Click **Add permissions** → **Create inline policy**
3. Click **JSON** tab and paste:

```json
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
      "Resource": "arn:aws:logs:us-east-2:YOUR_ACCOUNT_ID:log-group:/ecs/weather-service:*"
    }
  ]
}
```

4. Replace `YOUR_ACCOUNT_ID` with your AWS account ID
5. Policy name: `CloudWatchLogsAccess`
6. Click **Create policy**

**✅ Role 2 Complete!** Copy the Role ARN.

---

## Role 3: GitHub Actions OIDC Role

### Step 1: Create OIDC Provider (One-time setup)

1. Go to **IAM Console** → **Identity providers** → **Add provider**
2. Provider type: **OpenID Connect**
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Click **Get thumbprint**
5. Audience: `sts.amazonaws.com`
6. Add tags:
   - Key: `Project`, Value: `WeatherAlertService`
7. Click **Add provider**

### Step 2: Create the Role

1. Go to **IAM Console** → **Roles** → **Create role**
2. Select **Web identity** as trusted entity type
3. Identity provider: Choose `token.actions.githubusercontent.com` (the one you just created)
4. Audience: `sts.amazonaws.com`
5. GitHub organization: `matthew-goldman`
6. GitHub repository: `sezzle`
7. Click **Next**

### Step 3: Skip Managed Policies

1. Don't select any managed policies yet
2. Click **Next**

### Step 4: Name and Create

1. Role name: `GitHubActionsWeatherService`
2. Description: `GitHub Actions role for Weather Alert Service CI/CD`
3. Add tags:
   - Key: `Project`, Value: `WeatherAlertService`
4. Click **Create role**

### Step 5: Edit Trust Policy

1. Find the role you just created
2. Go to **Trust relationships** tab
3. Click **Edit trust policy**
4. Replace with this JSON:

```json
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
```

5. Replace `YOUR_ACCOUNT_ID` with your AWS account ID
6. Click **Update policy**

### Step 6: Add ECR and ECS Permissions

1. Click **Add permissions** → **Create inline policy**
2. Click **JSON** tab and paste:

```json
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
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/WeatherServiceECSTaskExecutionRole",
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/WeatherServiceECSTaskRole"
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
      "Resource": "arn:aws:logs:us-east-2:YOUR_ACCOUNT_ID:log-group:/ecs/weather-service:*"
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
```

3. Replace all instances of `YOUR_ACCOUNT_ID` with your AWS account ID
4. Policy name: `GitHubActionsPolicy`
5. Click **Create policy**

### Step 7: Add Terraform Permissions (if using Terraform from GitHub Actions)

1. Click **Add permissions** → **Create inline policy**
2. Click **JSON** tab and paste:

```json
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
      "Resource": "arn:aws:dynamodb:us-east-2:YOUR_ACCOUNT_ID:table/terraform-state-lock"
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
```

3. Replace `YOUR_ACCOUNT_ID` with your AWS account ID
4. Policy name: `TerraformExecutionPolicy`
5. Click **Create policy**

**✅ Role 3 Complete!** Copy the Role ARN.

---

## Summary and Next Steps

You should now have 3 roles created:

| Role Name | ARN |
|-----------|-----|
| WeatherServiceECSTaskExecutionRole | arn:aws:iam::YOUR_ACCOUNT_ID:role/WeatherServiceECSTaskExecutionRole |
| WeatherServiceECSTaskRole | arn:aws:iam::YOUR_ACCOUNT_ID:role/WeatherServiceECSTaskRole |
| GitHubActionsWeatherService | arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsWeatherService |

### Configure GitHub Repository

1. Go to your GitHub repository: `https://github.com/matthew-goldman/sezzle`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add secret:
   - Name: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsWeatherService`

### Configure Terraform

The Terraform code will automatically use the IAM roles you created. Just make sure the role names match exactly:
- `WeatherServiceECSTaskExecutionRole`
- `WeatherServiceECSTaskRole`

If you used different names, update them in `deployments/terraform/main.tf`.

---

## Verification

To verify your setup:

```bash
# Check if roles exist
aws iam get-role --role-name WeatherServiceECSTaskExecutionRole
aws iam get-role --role-name WeatherServiceECSTaskRole
aws iam get-role --role-name GitHubActionsWeatherService

# List attached policies
aws iam list-attached-role-policies --role-name WeatherServiceECSTaskExecutionRole
aws iam list-role-policies --role-name WeatherServiceECSTaskExecutionRole

# Test GitHub Actions assume role (requires configured GitHub OIDC)
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsWeatherService \
  --role-session-name test-session \
  --web-identity-token "YOUR_GITHUB_TOKEN"
```

---

## Troubleshooting

### "Access Denied" when running Terraform

**Solution**: Add more permissions to GitHubActionsWeatherService role for the specific AWS service causing the error.

### ECS tasks fail to start

**Solution**: Check that WeatherServiceECSTaskExecutionRole has:
- AmazonECSTaskExecutionRolePolicy
- SecretsManagerAccess (if using Secrets Manager)

### GitHub Actions can't push to ECR

**Solution**: Verify GitHubActionsWeatherService has ECR permissions and the trust policy includes your GitHub repository.

### Can't find your Account ID

Run this command:
```bash
aws sts get-caller-identity --query Account --output text
```

---

## Security Best Practices

✅ **Least Privilege**: Only grant permissions needed for the specific task
✅ **Resource-Specific**: Use resource ARNs instead of "*" where possible  
✅ **Condition Keys**: Use IAM conditions to further restrict access
✅ **Regular Audits**: Review and update policies quarterly
✅ **Enable CloudTrail**: Monitor IAM role usage

---

## Alternative: Use the Automated Script

Instead of manual console setup, you can use the automated script:

```bash
chmod +x scripts/setup-iam.sh
./scripts/setup-iam.sh
```

This creates all roles and policies automatically!
