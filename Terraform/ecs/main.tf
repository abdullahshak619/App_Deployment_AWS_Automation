provider "aws" {
  region = "us-east-1"
}

# Variables for reuse
variable "aws_account_id" {
  default = "171171308751"  # Replace with your AWS account ID
}

variable "ecs_cluster_name" {
  default = "nginx-ecs-cluster"
}

variable "ecs_service_name" {
  default = "nginx-service"
}

variable "ecs_task_family" {
  default = "nginx-task"
}

variable "ecr_repo_name" {
  default = "my-nginx-repo"
}

variable "vpc_id" {
  description = "VPC to launch ECS resources"
}

variable "subnet_ids" {
  type = list(string)
  description = "List of private subnets in your VPC"
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecs_cluster_name
}


# Security Group for ECS Service
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-service-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "nginx_task" {
  family                   = var.ecs_task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "nginx-container"
      image     = "${var.aws_account_id}.dkr.ecr.us-east-1.amazonaws.com/${var.ecr_repo_name}:20"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "nginx_service" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  
}
