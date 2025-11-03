#!/bin/bash
set -e

REGION="us-west-2"
BUCKET_NAME="deepseek-ocr-deployment-assets"

echo "=========================================="
echo "DeepSeek-OCR Fast Redeploy"
echo "=========================================="
echo ""

# Step 1: Upload updated code to S3
echo "Step 1: Uploading updated code to S3..."
aws s3 cp app/streamlit_app.py s3://${BUCKET_NAME}/app/streamlit_app.py --region ${REGION}
aws s3 cp app/api_server.py s3://${BUCKET_NAME}/app/api_server.py --region ${REGION}
aws s3 cp app/model_engine.py s3://${BUCKET_NAME}/app/model_engine.py --region ${REGION}
aws s3 cp requirements.txt s3://${BUCKET_NAME}/requirements.txt --region ${REGION}
echo "✓ Code uploaded to S3"
echo ""

# Step 2: Get current instance ID
echo "Step 2: Getting current instance ID..."
INSTANCE_ID=$(terraform -chdir=terraform output -raw ec2_instance_id 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ]; then
    echo "⚠️  No instance found in Terraform state"
    echo "Proceeding with fresh deployment..."
else
    echo "Current instance: $INSTANCE_ID"
    echo ""
    
    # Step 3: Remove instance from Terraform state
    echo "Step 3: Removing instance from Terraform state..."
    terraform -chdir=terraform state rm aws_lb_target_group_attachment.api 2>/dev/null || echo "  (api attachment not in state)"
    terraform -chdir=terraform state rm aws_lb_target_group_attachment.frontend 2>/dev/null || echo "  (frontend attachment not in state)"
    echo "✓ Instance removed from state"
    echo ""
    
    # Step 4: Terminate old instance
    echo "Step 4: Terminating old instance..."
    aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION} --output json > /dev/null
    echo "✓ Instance ${INSTANCE_ID} terminating in background"
    echo ""
fi

# Step 5: Remove EC2 instance from state if it exists
echo "Step 5: Ensuring clean state..."
terraform -chdir=terraform state rm aws_instance.deepseek_ocr 2>/dev/null || echo "  (instance not in state)"
echo ""

# Step 6: Deploy new instance
echo "Step 6: Deploying new instance with updated code..."
echo "This will take 2-3 minutes..."
echo ""

terraform -chdir=terraform apply -auto-approve

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

# Get new instance details
NEW_INSTANCE_ID=$(terraform -chdir=terraform output -raw ec2_instance_id)
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)

echo "New Instance ID: $NEW_INSTANCE_ID"
echo "ALB DNS: $ALB_DNS"
echo ""
echo "Endpoints:"
echo "  API:      http://${ALB_DNS}:8000"
echo "  Frontend: http://${ALB_DNS}:8501"
echo ""
echo "⏳ Services are initializing (15-20 minutes)..."
echo ""
echo "Monitor initialization:"
echo "  ./scripts/monitor_new_instance.sh"
echo ""
echo "Connect via SSM:"
echo "  aws ssm start-session --target ${NEW_INSTANCE_ID} --region ${REGION}"
echo ""
