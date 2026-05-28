provider "aws" {
  region = "eu-west-2" # Change to your preferred region
}

variable "project_name" {
  default = "housing-scraper"
}

# Shared Mailjet credentials (used by all instances)
variable "mj_apikey_public" { type = string }
variable "mj_apikey_private" {
  type      = string
  sensitive = true
}
variable "sender_email" { type = string }

# Per-instance configuration — add a new entry here for each search profile
variable "instances" {
  type = map(object({
    gumtree_link      = string
    rightmove_link    = string
    recipient_email   = string
    start_date_filter = string
    schedule          = string # cron expression, e.g. "cron(0 9 * * ? *)"
  }))
}

# --- VPC & Networking ---
# We use public subnets and assign public IPs to tasks to avoid NAT Gateway costs ($32+/mo).
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}

# --- Security Groups ---
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks"
  description = "Allow outbound traffic for scraper"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-sg" }
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs"
  description = "Allow EFS traffic from VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block] # More robust than SG-only
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-efs-sg" }
}

# --- EFS for Persistence ---
resource "aws_efs_file_system" "data" {
  creation_token = "${var.project_name}-data"
  encrypted      = true
  tags           = { Name = "${var.project_name}-efs" }
}

resource "aws_efs_mount_target" "data" {
  count           = 2
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# One EFS access point per instance, each rooted at /data/<instance-name>
resource "aws_efs_access_point" "data" {
  for_each       = var.instances
  file_system_id = aws_efs_file_system.data.id
  posix_user {
    gid = 1000 # Matches 'node' user in Dockerfile
    uid = 1000
  }
  root_directory {
    path = "/data/${each.key}"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
  tags = { Name = "${var.project_name}-${each.key}-ap" }
}

# --- ECR Repository ---
resource "aws_ecr_repository" "app" {
  name         = var.project_name
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the latest image"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 1
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# --- IAM Roles ---
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Grant task execution role permission to setup EFS (required for Fargate EFS mounting)
resource "aws_iam_role_policy" "ecs_task_execution_efs" {
  name = "efs-setup"
  role = aws_iam_role.ecs_task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:DescribeFileSystems"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Grant task role permission to mount EFS
resource "aws_iam_role_policy" "efs_access" {
  name = "efs-access"
  role = aws_iam_role.ecs_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:DescribeFileSystems"
      ]
      Resource = "*"
    }]
  })
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# --- Per-Instance Resources ---

resource "aws_cloudwatch_log_group" "ecs" {
  for_each          = var.instances
  name              = "/ecs/${var.project_name}/${each.key}"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "app" {
  for_each                 = var.instances
  family                   = "${var.project_name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "${var.project_name}-${each.key}"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true

    environment = [
      { name = "DATA_DIR", value = "/app/data" },
      { name = "GUMTREE_LINK", value = each.value.gumtree_link },
      { name = "RIGHTMOVE_LINK", value = each.value.rightmove_link },
      { name = "MJ_APIKEY_PUBLIC", value = var.mj_apikey_public },
      { name = "MJ_APIKEY_PRIVATE", value = var.mj_apikey_private },
      { name = "SENDER_EMAIL", value = var.sender_email },
      { name = "RECIPIENT_EMAIL", value = each.value.recipient_email },
      { name = "START_DATE_FILTER", value = each.value.start_date_filter },
      { name = "SEND_EMAIL", value = "true" }
    ]

    mountPoints = [{
      sourceVolume  = "persistent-data"
      containerPath = "/app/data"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  volume {
    name = "persistent-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.data.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.data[each.key].id
        iam             = "ENABLED"
      }
    }
  }
}

# --- EventBridge Scheduler Role ---
resource "aws_iam_role" "ecs_events" {
  name = "${var.project_name}-event-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_events_run_task" {
  name = "ecs-run-task"
  role = aws_iam_role.ecs_events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "arn:aws:ecs:eu-west-2:*:task-definition/${var.project_name}-*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.ecs_task_role.arn]
      }
    ]
  })
}

# --- Scheduled Tasks ---
resource "aws_cloudwatch_event_rule" "daily_scrape" {
  for_each            = var.instances
  name                = "${var.project_name}-${each.key}-scrape"
  description         = "Triggers the housing scraper for ${each.key}"
  schedule_expression = each.value.schedule
}

resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {
  for_each  = var.instances
  rule      = aws_cloudwatch_event_rule.daily_scrape[each.key].name
  target_id = "run-scraper-task-${each.key}"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.ecs_events.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.app[each.key].arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = aws_subnet.public[*].id
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = true
    }
  }

  # Ensure mount targets are ready before task runs
  depends_on = [aws_efs_mount_target.data]
}

# --- Outputs ---
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "event_rule_names" {
  value = { for k, v in aws_cloudwatch_event_rule.daily_scrape : k => v.name }
}
