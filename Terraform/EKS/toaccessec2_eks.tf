# provider "aws" {
#  region = "us-east-1"
# }

resource "tls_private_key" "eks_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "eks-key"
  public_key = tls_private_key.eks_key.public_key_openssh
}

resource "aws_secretsmanager_secret" "eks_ssh_key" {
  name = "eks-ec2-private-key"
}

resource "aws_secretsmanager_secret_version" "eks_ssh_key_version" {
  secret_id     = aws_secretsmanager_secret.eks_ssh_key.id
  secret_string = tls_private_key.eks_key.private_key_pem
}


# ------------------------------------------------------
# 1. IAM Role for EC2 to access EKS
# ------------------------------------------------------
resource "aws_iam_role" "eks_access_role" {
  name = "eks-access-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}



resource "aws_iam_role_policy_attachment" "eks_full_access" {
  role       = aws_iam_role.eks_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFullAccess"
}

# Optional: Allow reading secrets
resource "aws_iam_role_policy_attachment" "secretsmanager_read" {
  role       = aws_iam_role.eks_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_instance_profile" "eks_profile" {
  name = "eks-access-instance-profile"
  role = aws_iam_role.eks_access_role.name
}

# ------------------------------------------------------
# 2. Store EKS credentials in Secrets Manager (example)
# ------------------------------------------------------
resource "aws_secretsmanager_secret" "eks_secret" {
  name = "eks-access-creds"
}

resource "aws_secretsmanager_secret_version" "eks_secret_version" {
  secret_id     = aws_secretsmanager_secret.eks_secret.id
  secret_string = jsonencode({
    cluster_name = "my-eks-cluster"
    region       = "us-east-1"
  })
}

# ------------------------------------------------------
# 3. EC2 Instance with Ubuntu
# ------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "eks-admin-sg"
  description = "Allow SSH and HTTPS"
  vpc_id      = "vpc-074980b5d9a132964"  # Replace or use data lookup

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-admin-sg"
  }
}


resource "aws_instance" "eks_admin_ec2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = "subnet-04d29c00845f2cc04"   # change as per your requirement ,public subnet
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.eks_profile.name
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]

 # Replace with your SSH key

  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y unzip curl jq awscli

              # Install kubectl
              curl -o kubectl https://s3.us-east-1.amazonaws.com/amazon-eks/1.28.2/2023-10-23/bin/linux/amd64/kubectl
              chmod +x ./kubectl
              mv ./kubectl /usr/local/bin/

              # Install eksctl
              curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
              mv /tmp/eksctl /usr/local/bin

              # Pull secret (optional demo)
              aws secretsmanager get-secret-value --secret-id eks-access-creds --region us-east-1
              EOF

  tags = {
    Name = "eks-admin-ec2"
  }
}

# ------------------------------------------------------
# 4. Output
# ------------------------------------------------------
output "ec2_public_ip" {
  value = aws_instance.eks_admin_ec2.public_ip
}

output "secret_arn" {
  value = aws_secretsmanager_secret.eks_secret.arn
}
