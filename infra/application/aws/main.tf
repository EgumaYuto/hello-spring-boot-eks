terraform {
  backend "s3" {
    bucket = "hello-spring-boot-eks-tfstate"
    key    = "aws/application"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = "ap-northeast-1"
}
