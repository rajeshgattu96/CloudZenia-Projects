resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = var.log_group
  retention_in_days = 14
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name}-cluster"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.name}-task-exec-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name}-task-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "${var.name}-secrets-policy"
  role = aws_iam_role.ecs_task_execution_role.id  

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Effect": "Allow",
      "Resource": "${var.db_secret_arn}"
    }
  ]
}
EOF
}


resource "aws_ecs_task_definition" "wordpress_task" {
  family                   = "${var.name}-wordpress"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = <<DEFS
[
  {
    "name": "wordpress",
    "image": "${var.wordpress_image}",
    "essential": true,
    "portMappings": [
      {
        "containerPort": 80,
        "protocol": "tcp"
      }
    ],
    "environment": [
      { "name": "WORDPRESS_DB_HOST", "value": "${var.rds_endpoint}" },
      { "name": "WORDPRESS_DB_USER", "value": "${var.rds_db_user}" },
      { "name": "WORDPRESS_DB_NAME", "value": "${var.rds_db_name}" }
    ],
    "secrets": [
      {
        "name": "WORDPRESS_DB_PASSWORD",
        "valueFrom": "${var.db_secret_arn}:password::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${var.log_group}",
        "awslogs-region": "${var.region}",
        "awslogs-stream-prefix": "wordpress"
      }
    }
  }
]
DEFS
}

resource "aws_ecs_task_definition" "microservice_task" {
  family                   = "${var.name}-micro"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = <<DEFS
[
  {
    "name": "microservice",
    "image": "${var.micro_image}",
    "essential": true,
    "portMappings": [
      {
        "containerPort": 8080,
        "protocol": "tcp"
      }
    ],
    "environment": [
      { "name": "MESSAGE", "value": "Hello from Microservice" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${var.log_group}",
        "awslogs-region": "${var.region}",
        "awslogs-stream-prefix": "micro"
      }
    }
  }
]
DEFS
}

resource "aws_ecs_service" "wordpress_service" {
  name            = "${var.name}-wp-svc"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.wordpress_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.service_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.tg_arn_wordpress
    container_name   = "wordpress"
    container_port   = 80
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]
}

resource "aws_ecs_service" "microservice_service" {
  name            = "${var.name}-micro-svc"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.microservice_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.service_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.tg_arn_microservice
    container_name   = "microservice"
    container_port   = 8080
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]
}
