# Scripts

## Setup Scripts
- **setup-aws.sh** - Complete AWS setup (S3, IAM, ECR, Secrets, DynamoDB)
- **setup.sh** - Local development setup

## Cleanup Scripts
- **destroy-aws.sh** - Complete AWS resource cleanup

## Usage

### Initial Setup
```bash
export OPENWEATHER_API_KEY="your_key"
./scripts/setup-aws.sh
```

### Cleanup
```bash
./scripts/destroy-aws.sh
# Type "destroy" then "yes" to confirm
```