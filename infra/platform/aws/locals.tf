locals {
  name               = "hello-spring-boot-eks"
  region             = data.aws_region.current
  availability_zones = data.aws_availability_zones.available
  cidr_block         = "10.0.0.0/16"
  newbits            = 8
}
