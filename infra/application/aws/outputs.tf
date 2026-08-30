output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "region" {
  value = data.aws_region.current.region
}

output "vpc_id" {
  value = local.vpc_id
}

output "ecr_repository_url" {
  value = local.ecr_repository_url
}

output "namespace" {
  value = var.namespace
}

output "container_port" {
  value = var.container_port
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "aurora_port" {
  value = aws_rds_cluster.aurora.port
}

output "db_name" {
  value = var.db_name
}

# deploy.sh reads this secret to build the Kubernetes Secret the app consumes.
output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}
