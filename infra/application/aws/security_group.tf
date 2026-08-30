# Aurora: only reachable from the EKS pods on the MySQL port.
#
# Fargate pod ENIs are attached to the EKS-managed "cluster security group",
# so allowing that SG is what lets the app pods reach the database.
resource "aws_security_group" "aurora" {
  name        = "${var.app_name}-aurora"
  description = "Security group for the ${var.app_name} Aurora cluster"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.app_name}-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_cluster" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "MySQL from the EKS cluster (Fargate pods)"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "aurora_all" {
  security_group_id = aws_security_group.aurora.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
