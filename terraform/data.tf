data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# Only one pair of subnets exists on this platform (the "App" tier) and it is
# used both for the EKS control plane/nodes and for the Network Load Balancer
# exposing OneUptime (see helm/values.yaml's aws-load-balancer-subnets
# annotation).
data "aws_subnet" "a" {
  vpc_id = data.aws_vpc.selected.id

  filter {
    name   = "tag:Name"
    values = [var.subnet_a]
  }
}

data "aws_subnet" "b" {
  vpc_id = data.aws_vpc.selected.id

  filter {
    name   = "tag:Name"
    values = [var.subnet_b]
  }
}
