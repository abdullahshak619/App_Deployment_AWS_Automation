provider "aws" {
  region = "us-east-1"
}

# Generate an RSA key pair
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload the public key to AWS
resource "aws_key_pair" "example" {
  key_name   = "tf-keypair"
  public_key = tls_private_key.example.public_key_openssh
}

# Look up the latest Amazon Linux 2 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create a security group that allows SSH
resource "aws_security_group" "ssh" {
  name        = "allow-ssh"
  description = "Allow SSH access"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow access from any IP address
  }
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For demo purposes only; restrict in prod
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance
resource "aws_instance" "example" {
 # ami                         = data.aws_ami.amazon_linux.id
  ami                          = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.example.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]

  tags = {
    Name = "DemoEC2Instance"
  }
}

# Output the public IP of the instance
output "ec2_public_ip" {
  value = aws_instance.example.public_ip
}

