terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Generate RSA Key Pair
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "ec2_private_key" {
  name = "ec2-private-key"
}

resource "aws_secretsmanager_secret_version" "ec2_private_key_version" {
  secret_id     = aws_secretsmanager_secret.ec2_private_key.id
  secret_string = tls_private_key.example.private_key_pem
}

# Upload the public key to AWS EC2
resource "aws_key_pair" "example" {
  key_name   = "tf-keypair"
  public_key = tls_private_key.example.public_key_openssh
}

# Create VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "custom-vpc" }
}

# Create 2 subnets (you can duplicate to make 4)
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.1.0/24"
 ## map_public_ip_on_launch = true     # <-- enables public IP on launch

  availability_zone = "us-east-1a"
  tags = { Name = "subnet-1" }
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "subnet-2" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id
  tags = { Name = "custom-igw" }
}

# Route Table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "custom-rt" }
}

# Associate route table with subnets
resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.rt.id
}

# Security Group for SSH
resource "aws_security_group" "ssh" {
  name        = "allow-ssh"
  vpc_id      = aws_vpc.custom_vpc.id
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
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

# Lookup Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch EC2
resource "aws_instance" "example" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.ssh.id]
  key_name               = aws_key_pair.example.key_name
  associate_public_ip_address = true

  tags = {
    Name = "CustomEC2"
  }
}

# Output Public IP
output "ec2_public_ip" {
  value = aws_instance.example.public_ip
}

# Output Private Key Location
output "private_key_secret_arn" {
  value = aws_secretsmanager_secret.ec2_private_key.arn
}  
