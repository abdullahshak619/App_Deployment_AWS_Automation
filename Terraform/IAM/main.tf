##Commenting as I created manually
#resource "aws_iam_role" "ecs_task_execution_role" {
#  name = "github-action"

#  assume_role_policy = jsonencode({
#    Version = "2012-10-17",
#    Statement = [{
#      Effect = "Allow",
#      Principal = {
#        Service = "ecs-tasks.amazonaws.com"
#      },
#      Action = "sts:AssumeRole"
#    }]
#  })
#}
resource "aws_iam_role_policy_attachment" "ec2_task_exec_policy" {
  role = "github-action"
  #role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2FullAccess"
}
