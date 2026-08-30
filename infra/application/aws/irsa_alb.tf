########################################
# IRSA role for the AWS Load Balancer Controller
#
# The Helm-installed controller runs as the kube-system service account
# "aws-load-balancer-controller". This role lets that service account call the
# ELB/EC2 APIs it needs to create the ALB behind our Ingress.
########################################

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.app_name}-alb-controller"
  policy = file("${path.module}/alb_controller_iam_policy.json")
}

locals {
  oidc_provider_url = replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")
}

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.app_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
