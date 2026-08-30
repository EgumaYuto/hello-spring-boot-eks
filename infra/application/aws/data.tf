data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# Read the platform stack outputs (VPC, subnets, ECR) instead of passing them in.
data "terraform_remote_state" "platform" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = "hello-spring-boot-eks-tfstate"
    key    = "aws/platform"
    region = "ap-northeast-1"
  }
}

locals {
  vpc_id             = data.terraform_remote_state.platform.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.platform.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.platform.outputs.private_subnet_ids
  ecr_repository_url = data.terraform_remote_state.platform.outputs.ecr_repository_url
}
