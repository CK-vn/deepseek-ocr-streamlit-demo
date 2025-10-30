# Use AWS Deep Learning AMI with CUDA pre-installed
# AMI: Deep Learning Base AMI with Single CUDA (Ubuntu 22.04)
# This AMI comes with CUDA, cuDNN, and NVIDIA drivers pre-installed

# EC2 Instance
resource "aws_instance" "deepseek_ocr" {
  ami                    = "ami-068b3c2eff653a1a1"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  user_data = file("${path.module}/user_data.sh")

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = {
    Name = "${var.project_name}-instance"
  }

  # Ensure IAM role is created before instance
  depends_on = [
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
    aws_iam_role_policy_attachment.cloudwatch_logs,
    aws_iam_role_policy_attachment.s3_access
  ]
}
