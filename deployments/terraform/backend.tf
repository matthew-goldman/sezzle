terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "sezzle-weather-terraform-state"
    key            = "weather-service/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "weather-alert-service"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/matthew-goldman/sezzle"
    }
  }
}
