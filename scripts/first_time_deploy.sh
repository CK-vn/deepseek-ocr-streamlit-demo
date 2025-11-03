#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION="us-west-2"
BUCKET_NAME="deepseek-ocr-deployment-assets"
PROJECT_NAME="DeepSeek-OCR"

echo -e "${BLUE}=========================================="
echo "  ${PROJECT_NAME} - First Time Deployment"
echo "==========================================${NC}"
echo ""

# Function to print status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 1: Verify Prerequisites
echo -e "${BLUE}Step 1: Verifying Prerequisites${NC}"
echo "-----------------------------------"

# Check Terraform
if command_exists terraform; then
    TERRAFORM_VERSION=$(terraform version | head -n1 | cut -d'v' -f2)
    print_success "Terraform installed: v${TERRAFORM_VERSION}"
else
    print_error "Terraform not found. Please install Terraform first."
    echo "  Visit: https://www.terraform.io/downloads"
    exit 1
fi

# Check AWS CLI
if command_exists aws; then
    AWS_VERSION=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
    print_success "AWS CLI installed: v${AWS_VERSION}"
else
    print_error "AWS CLI not found. Please install AWS CLI first."
    echo "  Visit: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
print_status "Checking AWS credentials..."
if aws sts get-caller-identity --region ${REGION} >/dev/null 2>&1; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)
    print_success "AWS credentials configured"
    echo "  Account: ${AWS_ACCOUNT}"
    echo "  User/Role: ${AWS_USER}"
    echo "  Region: ${REGION}"
else
    print_error "AWS credentials not configured or invalid"
    echo "  Run: aws configure"
    exit 1
fi

# Check Python
if command_exists python3; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    print_success "Python installed: v${PYTHON_VERSION}"
else
    print_warning "Python3 not found (only needed for local testing)"
fi

echo ""

# Step 2: Verify Project Structure
echo -e "${BLUE}Step 2: Verifying Project Structure${NC}"
echo "-----------------------------------"

REQUIRED_FILES=(
    "app/api_server.py"
    "app/model_engine.py"
    "app/streamlit_app.py"
    "requirements.txt"
    "terraform/main.tf"
    "terraform/variables.tf"
)

ALL_FILES_EXIST=true
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "Found: $file"
    else
        print_error "Missing: $file"
        ALL_FILES_EXIST=false
    fi
done

if [ "$ALL_FILES_EXIST" = false ]; then
    print_error "Required files are missing. Please ensure all project files are present."
    exit 1
fi

echo ""

# Step 3: Create S3 Bucket for Deployment Assets
echo -e "${BLUE}Step 3: Setting Up S3 Deployment Bucket${NC}"
echo "-----------------------------------"

if aws s3 ls "s3://${BUCKET_NAME}" --region ${REGION} 2>/dev/null; then
    print_warning "S3 bucket already exists: ${BUCKET_NAME}"
else
    print_status "Creating S3 bucket: ${BUCKET_NAME}"
    aws s3 mb "s3://${BUCKET_NAME}" --region ${REGION}
    
    # Enable versioning
    print_status "Enabling versioning on S3 bucket..."
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled \
        --region ${REGION}
    
    print_success "S3 bucket created and configured"
fi

echo ""

# Step 4: Upload Application Code to S3
echo -e "${BLUE}Step 4: Uploading Application Code to S3${NC}"
echo "-----------------------------------"

print_status "Uploading app files..."
aws s3 cp app/api_server.py "s3://${BUCKET_NAME}/app/api_server.py" --region ${REGION}
aws s3 cp app/model_engine.py "s3://${BUCKET_NAME}/app/model_engine.py" --region ${REGION}
aws s3 cp app/streamlit_app.py "s3://${BUCKET_NAME}/app/streamlit_app.py" --region ${REGION}

print_status "Uploading requirements.txt..."
aws s3 cp requirements.txt "s3://${BUCKET_NAME}/requirements.txt" --region ${REGION}

print_success "Application code uploaded to S3"

# List uploaded files
print_status "Uploaded files:"
aws s3 ls "s3://${BUCKET_NAME}/" --recursive --region ${REGION} | awk '{print "  " $4}'

echo ""

# Step 5: Initialize Terraform
echo -e "${BLUE}Step 5: Initializing Terraform${NC}"
echo "-----------------------------------"

cd terraform

if [ -d ".terraform" ]; then
    print_warning "Terraform already initialized"
else
    print_status "Running terraform init..."
    terraform init
    print_success "Terraform initialized"
fi

echo ""

# Step 6: Validate Terraform Configuration
echo -e "${BLUE}Step 6: Validating Terraform Configuration${NC}"
echo "-----------------------------------"

print_status "Running terraform validate..."
if terraform validate; then
    print_success "Terraform configuration is valid"
else
    print_error "Terraform validation failed"
    exit 1
fi

echo ""

# Step 7: Plan Terraform Deployment
echo -e "${BLUE}Step 7: Planning Infrastructure Deployment${NC}"
echo "-----------------------------------"

print_status "Running terraform plan..."
terraform plan -out=tfplan

print_success "Terraform plan created"
echo ""
print_warning "Review the plan above carefully before proceeding."
echo ""

# Ask for confirmation
read -p "Do you want to proceed with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_warning "Deployment cancelled by user"
    rm -f tfplan
    exit 0
fi

echo ""

# Step 8: Apply Terraform Configuration
echo -e "${BLUE}Step 8: Deploying Infrastructure${NC}"
echo "-----------------------------------"

print_status "Running terraform apply..."
print_warning "This will take 5-10 minutes..."
echo ""

terraform apply tfplan

print_success "Infrastructure deployed successfully!"
echo ""

# Clean up plan file
rm -f tfplan

# Step 9: Retrieve Deployment Information
echo -e "${BLUE}Step 9: Retrieving Deployment Information${NC}"
echo "-----------------------------------"

INSTANCE_ID=$(terraform output -raw ec2_instance_id 2>/dev/null || echo "")
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")

if [ -n "$INSTANCE_ID" ]; then
    print_success "Instance ID: ${INSTANCE_ID}"
else
    print_error "Could not retrieve instance ID"
fi

if [ -n "$ALB_DNS" ]; then
    print_success "ALB DNS: ${ALB_DNS}"
else
    print_error "Could not retrieve ALB DNS"
fi

if [ -n "$VPC_ID" ]; then
    print_success "VPC ID: ${VPC_ID}"
fi

echo ""

# Step 10: Display Next Steps
echo -e "${GREEN}=========================================="
echo "  Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${YELLOW}⏳ IMPORTANT: Services are still initializing${NC}"
echo ""
echo "The EC2 instance is now running, but it needs 15-20 minutes to:"
echo "  • Install NVIDIA drivers and CUDA toolkit"
echo "  • Install Python dependencies (PyTorch, transformers, etc.)"
echo "  • Compile Flash Attention 2 (10-15 minutes)"
echo "  • Download DeepSeek-OCR model weights (~10GB)"
echo "  • Start API and Frontend services"
echo ""
echo -e "${BLUE}Endpoints (will be available after initialization):${NC}"
echo "  API:      http://${ALB_DNS}:8000"
echo "  Frontend: http://${ALB_DNS}:8501"
echo "  API Docs: http://${ALB_DNS}:8000/docs"
echo "  Health:   http://${ALB_DNS}:8000/health"
echo ""
echo -e "${BLUE}Monitoring Commands:${NC}"
echo "  # Monitor initialization progress:"
echo "  cd .. && ./scripts/monitor_new_instance.sh"
echo ""
echo "  # Connect to instance via SSM:"
echo "  aws ssm start-session --target ${INSTANCE_ID} --region ${REGION}"
echo ""
echo "  # Check service status (after connecting via SSM):"
echo "  sudo systemctl status deepseek-api"
echo "  sudo systemctl status deepseek-frontend"
echo ""
echo "  # View logs (after connecting via SSM):"
echo "  sudo journalctl -u deepseek-api -f"
echo "  sudo tail -f /var/log/user-data.log"
echo ""
echo -e "${BLUE}Testing:${NC}"
echo "  # Test endpoints (after services are ready):"
echo "  cd .. && python3 scripts/test_ocr_endpoint.py"
echo ""
echo -e "${BLUE}Cost Information:${NC}"
echo "  Estimated hourly cost: ~\$0.75-\$1.00/hour"
echo "  • EC2 g6.xlarge: ~\$0.70/hour"
echo "  • Application Load Balancer: ~\$0.05/hour"
echo ""
echo -e "${YELLOW}Remember to destroy resources when done to avoid charges:${NC}"
echo "  cd terraform && terraform destroy"
echo ""
echo -e "${GREEN}Deployment script completed successfully!${NC}"
echo ""
