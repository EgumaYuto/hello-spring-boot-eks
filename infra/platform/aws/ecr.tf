resource "aws_ecr_repository" "app" {
  name = local.name
}
