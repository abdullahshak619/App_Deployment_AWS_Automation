aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com

docker pull <imagename>

docker tag <imagename>:latest <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com/<reponame>:latest

docker push <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com/<reponame>:latest
