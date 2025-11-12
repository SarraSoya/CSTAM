module "vpc" {
  source = "./modules/vpc"
}

module "spark" {
  source    = "./modules/spark"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]
  key_name  = var.key_name
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "key_name" {
  description = "AWS key pair name"
  type        = string
}