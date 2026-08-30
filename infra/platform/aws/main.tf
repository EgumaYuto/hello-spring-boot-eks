terraform {
  # NOTE: The state bucket must already exist. See README (bootstrap section):
  #   aws s3 mb s3://hello-spring-boot-eks-tfstate --region ap-northeast-1
  backend "s3" {
    bucket = "hello-spring-boot-eks-tfstate"
    key    = "aws/platform"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = "ap-northeast-1"
}
