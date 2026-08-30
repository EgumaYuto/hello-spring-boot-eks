resource "aws_vpc" "vpc" {
  cidr_block           = local.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

# Private subnets host the Fargate pods and Aurora. The
# "kubernetes.io/role/internal-elb" tag lets the AWS Load Balancer Controller
# auto-discover them for internal load balancers.
resource "aws_subnet" "private" {
  count = length(local.availability_zones.names)

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(local.cidr_block, local.newbits, length(local.availability_zones.names) + count.index)
  availability_zone = element(local.availability_zones.names, count.index)

  tags = {
    Name                              = "${local.name}-private-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Public subnets host the internet-facing ALB created by the Ingress. The
# "kubernetes.io/role/elb" tag lets the controller auto-discover them.
resource "aws_subnet" "public" {
  count = length(local.availability_zones.names)

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(local.cidr_block, local.newbits, count.index)
  availability_zone       = element(local.availability_zones.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${local.name}-public-${count.index}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = local.name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Single NAT gateway is enough for a learning environment; it gives the Fargate
# pods in the private subnets outbound access to pull images from ECR and reach
# STS / Secrets Manager. Revisit for production HA (one NAT per AZ).
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = local.name
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${local.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
