data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# Only one pair of subnets exists on this platform (the "App" tier) and it is
# used for everything: ECS Fargate task ENIs, the internal ALB, RDS/
# ElastiCache/EFS mount targets.
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
