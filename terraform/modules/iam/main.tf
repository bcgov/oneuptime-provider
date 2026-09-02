data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# One shared execution role for every service — it only needs to pull
# images, write logs, and read the shared Secrets Manager secret. Per-service
# task *roles* are created too, kept separate (and empty by default) so any
# service-specific AWS permissions added later (e.g. probe/runner needing S3
# access) don't have to be granted to every other service as well.
resource "aws_iam_role" "task_execution" {
  name               = "${var.name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_read_secret" {
  name = "${var.name}-read-secret"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.secret_arn]
      }
    ]
  })
}

resource "aws_iam_role" "task" {
  for_each = var.service_names

  name               = "${var.name}-${each.key}-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}
