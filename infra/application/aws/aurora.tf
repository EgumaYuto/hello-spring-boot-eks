resource "aws_db_subnet_group" "aurora" {
  name       = "${var.app_name}-aurora"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${var.app_name}-aurora"
  }
}

# MySQL does not allow some special characters in passwords; exclude them.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}"
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.app_name}-aurora"
  engine             = "aurora-mysql"
  engine_version     = var.aurora_engine_version
  engine_mode        = "provisioned"

  database_name   = var.db_name
  master_username = var.db_username
  master_password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  storage_encrypted   = true
  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1.0
  }

  tags = {
    Name = "${var.app_name}-aurora"
  }
}

resource "aws_rds_cluster_instance" "aurora" {
  identifier         = "${var.app_name}-aurora-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  instance_class     = "db.serverless"
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.app_name}/db"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_rds_cluster.aurora.endpoint
    port     = aws_rds_cluster.aurora.port
    dbname   = var.db_name
  })
}
