# Lambda function to stop/start EC2 instance
resource "aws_lambda_function" "instance_scheduler" {
  count         = var.enable_scheduling ? 1 : 0
  filename      = "instance_scheduler.zip"
  function_name = "${var.project_name}-instance-scheduler"
  role          = aws_iam_role.lambda_scheduler_role[0].arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  timeout       = 60

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID = aws_instance.deepseek_ocr.id
    }
  }

  tags = {
    Name = "${var.project_name}-instance-scheduler"
  }
}

# Create the Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "instance_scheduler.zip"
  source {
    content  = <<EOF
import boto3
import json
import os

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    instance_id = os.environ['INSTANCE_ID']
    action = event.get('action', 'stop')
    
    try:
        if action == 'stop':
            response = ec2.stop_instances(InstanceIds=[instance_id])
            print(f"Stopping instance {instance_id}")
        elif action == 'start':
            response = ec2.start_instances(InstanceIds=[instance_id])
            print(f"Starting instance {instance_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully {action}ped instance {instance_id}')
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error {action}ping instance: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_scheduler_role" {
  count = var.enable_scheduling ? 1 : 0
  name  = "${var.project_name}-lambda-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-scheduler-role"
  }
}

# IAM Policy for Lambda to manage EC2 instances
resource "aws_iam_policy" "lambda_ec2_policy" {
  count       = var.enable_scheduling ? 1 : 0
  name        = "${var.project_name}-lambda-ec2-policy"
  description = "Policy for Lambda to start/stop EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-instance-scheduler*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-ec2-policy"
  }
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_ec2_policy_attachment" {
  count      = var.enable_scheduling ? 1 : 0
  role       = aws_iam_role.lambda_scheduler_role[0].name
  policy_arn = aws_iam_policy.lambda_ec2_policy[0].arn
}

# Attach basic execution role for Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count      = var.enable_scheduling ? 1 : 0
  role       = aws_iam_role.lambda_scheduler_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# EventBridge rule to stop instance at 9 PM UTC+7 (weekdays only: Mon-Thu)
resource "aws_cloudwatch_event_rule" "stop_instance_weekday" {
  count               = var.enable_scheduling ? 1 : 0
  name                = "${var.project_name}-stop-instance-weekday"
  description         = "Stop EC2 instance at 9 PM UTC+7 on weekdays (${var.stop_time_utc}:00 UTC)"
  schedule_expression = "cron(0 ${var.stop_time_utc} ? * MON-THU *)"

  tags = {
    Name = "${var.project_name}-stop-instance-weekday-rule"
  }
}

# EventBridge rule to start instance at 9 AM UTC+7 (weekdays only: Tue-Fri)
resource "aws_cloudwatch_event_rule" "start_instance_weekday" {
  count               = var.enable_scheduling ? 1 : 0
  name                = "${var.project_name}-start-instance-weekday"
  description         = "Start EC2 instance at 9 AM UTC+7 on weekdays (${var.start_time_utc}:00 UTC)"
  schedule_expression = "cron(0 ${var.start_time_utc} ? * TUE-FRI *)"

  tags = {
    Name = "${var.project_name}-start-instance-weekday-rule"
  }
}

# EventBridge rule to stop instance for weekend (Friday 9 PM UTC+7)
resource "aws_cloudwatch_event_rule" "stop_instance_weekend" {
  count               = var.enable_scheduling ? 1 : 0
  name                = "${var.project_name}-stop-instance-weekend"
  description         = "Stop EC2 instance for weekend at 9 PM UTC+7 on Friday (${var.stop_time_utc}:00 UTC)"
  schedule_expression = "cron(0 ${var.stop_time_utc} ? * FRI *)"

  tags = {
    Name = "${var.project_name}-stop-instance-weekend-rule"
  }
}

# EventBridge rule to start instance after weekend (Monday 9 AM UTC+7)
resource "aws_cloudwatch_event_rule" "start_instance_weekend" {
  count               = var.enable_scheduling ? 1 : 0
  name                = "${var.project_name}-start-instance-weekend"
  description         = "Start EC2 instance after weekend at 9 AM UTC+7 on Monday (${var.start_time_utc}:00 UTC)"
  schedule_expression = "cron(0 ${var.start_time_utc} ? * MON *)"

  tags = {
    Name = "${var.project_name}-start-instance-weekend-rule"
  }
}

# EventBridge target for weekday stop rule
resource "aws_cloudwatch_event_target" "stop_instance_weekday_target" {
  count     = var.enable_scheduling ? 1 : 0
  rule      = aws_cloudwatch_event_rule.stop_instance_weekday[0].name
  target_id = "StopInstanceWeekdayTarget"
  arn       = aws_lambda_function.instance_scheduler[0].arn

  input = jsonencode({
    action = "stop"
  })
}

# EventBridge target for weekday start rule
resource "aws_cloudwatch_event_target" "start_instance_weekday_target" {
  count     = var.enable_scheduling ? 1 : 0
  rule      = aws_cloudwatch_event_rule.start_instance_weekday[0].name
  target_id = "StartInstanceWeekdayTarget"
  arn       = aws_lambda_function.instance_scheduler[0].arn

  input = jsonencode({
    action = "start"
  })
}

# EventBridge target for weekend stop rule
resource "aws_cloudwatch_event_target" "stop_instance_weekend_target" {
  count     = var.enable_scheduling ? 1 : 0
  rule      = aws_cloudwatch_event_rule.stop_instance_weekend[0].name
  target_id = "StopInstanceWeekendTarget"
  arn       = aws_lambda_function.instance_scheduler[0].arn

  input = jsonencode({
    action = "stop"
  })
}

# EventBridge target for weekend start rule
resource "aws_cloudwatch_event_target" "start_instance_weekend_target" {
  count     = var.enable_scheduling ? 1 : 0
  rule      = aws_cloudwatch_event_rule.start_instance_weekend[0].name
  target_id = "StartInstanceWeekendTarget"
  arn       = aws_lambda_function.instance_scheduler[0].arn

  input = jsonencode({
    action = "start"
  })
}

# Lambda permission for EventBridge to invoke the function (weekday stop)
resource "aws_lambda_permission" "allow_eventbridge_stop_weekday" {
  count         = var.enable_scheduling ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeStopWeekday"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instance_weekday[0].arn
}

# Lambda permission for EventBridge to invoke the function (weekday start)
resource "aws_lambda_permission" "allow_eventbridge_start_weekday" {
  count         = var.enable_scheduling ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeStartWeekday"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instance_weekday[0].arn
}

# Lambda permission for EventBridge to invoke the function (weekend stop)
resource "aws_lambda_permission" "allow_eventbridge_stop_weekend" {
  count         = var.enable_scheduling ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeStopWeekend"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instance_weekend[0].arn
}

# Lambda permission for EventBridge to invoke the function (weekend start)
resource "aws_lambda_permission" "allow_eventbridge_start_weekend" {
  count         = var.enable_scheduling ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeStartWeekend"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instance_weekend[0].arn
}
