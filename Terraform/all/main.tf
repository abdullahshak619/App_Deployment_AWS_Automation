terraform {
  backend "s3" {
    bucket         = "terraform-state-bucketlko"
    key            = "all/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

###########################
# S3 BUCKET FOR TERRAFORM STATE
###########################
resource "aws_s3_bucket" "example" {
  bucket        = "my-aut-bu3cket-name-12456" # Must be globally unique
  force_destroy = true

  tags = {
    Name = "TerraformStateBucket"
  }
}

###########################
# VARIABLES
###########################
variable "aws_account_id" {
  default = "171171308751"
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

###########################
# NETWORKING (VPC + SUBNETS)
###########################
resource "aws_vpc" "custom_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "custom-vpc" }
}

resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "subnet-1" }
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "subnet-2" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id
  tags = { Name = "custom-igw" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "custom-rt" }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.rt.id
}

###########################
# ECR
###########################
resource "aws_ecr_repository" "example" {
  name = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

###########################
# IAM ROLES
###########################
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

###########################
# ECS RESOURCES
###########################
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecs_cluster_name
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-service-sg"
  vpc_id      = aws_vpc.custom_vpc.id
  description = "Allow HTTP inbound traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "nginx_task" {
  family                   = var.ecs_task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "nginx-container",
    image     = "${var.aws_account_id}.dkr.ecr.us-east-1.amazonaws.com/${var.ecr_repo_name}:20",
    essential = true,
    portMappings = [{
      containerPort = 80,
      hostPort      = 80,
      protocol      = "tcp"
    }]
  }])
}

resource "aws_ecs_service" "nginx_service" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_execution_policy]
}

###########################
# OPTIONAL: EC2 + KEY PAIR + SECRET MGMT
###########################
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_secretsmanager_secret" "ec2_private_key" {
  name = "ec2-private-key"
}

resource "aws_secretsmanager_secret_version" "ec2_private_key_version" {
  secret_id     = aws_secretsmanager_secret.ec2_private_key.id
  secret_string = tls_private_key.example.private_key_pem
}

resource "aws_key_pair" "example" {
  key_name   = "tf-keypair"
  public_key = tls_private_key.example.public_key_openssh
}

resource "aws_instance" "example" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
  key_name               = aws_key_pair.example.key_name
  associate_public_ip_address = true

  tags = {
    Name = "CustomEC2"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

output "ec2_public_ip" {
  value = aws_instance.example.public_ip
}


