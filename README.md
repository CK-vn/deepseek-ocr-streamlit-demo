# DeepSeek-OCR AWS Deployment

This project deploys DeepSeek-OCR, a vision-language model for optical character recognition, on AWS EC2 with both a web interface and OpenAI-compatible API endpoint.

## Architecture

The deployment includes:
- **Streamlit Frontend** (port 8501): Interactive web interface for OCR tasks
- **FastAPI Server** (port 8000): OpenAI-compatible REST API
- **Application Load Balancer**: Persistent DNS endpoint routing to both services
- **EC2 g6.xlarge Instance**: GPU-accelerated instance running both services
- **DeepSeek-OCR Model**: Vision-language model loaded in GPU memory

## Prerequisites

### Required Tools

1. **Terraform** (v1.0+)
   ```bash
   # Install on Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **AWS CLI** (v2.0+)
   ```bash
   # Install on Linux
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

3. **Python** (3.10+) - Only required for local testing
   ```bash
   python3 --version
   ```

### AWS Credentials Configuration

Configure your AWS credentials with appropriate permissions:

```bash
aws configure
```

You'll need to provide:
- AWS Access Key ID
- AWS Secret Access Key
- Default region: `us-west-2`
- Default output format: `json`

### Required IAM Permissions

Your AWS user/role must have permissions to create and manage:

- **EC2**: Instances, security groups, key pairs, AMI queries
- **VPC**: VPCs, subnets, internet gateways, route tables
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, instance profiles, policy attachments
- **Systems Manager**: Session Manager access

Minimum IAM policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:PassRole",
        "iam:GetRole",
        "iam:GetInstanceProfile",
        "ssm:StartSession",
        "ssm:DescribeSessions"
      ],
      "Resource": "*"
    }
  ]
}
```

### System Requirements

- **Local Machine**: Any OS with Terraform and AWS CLI installed
- **AWS Region**: us-west-2 (configurable in `terraform/variables.tf`)
- **EC2 Instance**: g6.xlarge with NVIDIA L4 GPU (24GB VRAM)
- **Storage**: 100GB EBS volume for OS, dependencies, and model weights (~10GB)
- **Estimated Cost**: ~$0.70/hour for g6.xlarge instance + ALB costs

## Deployment Instructions

### Step 1: Clone or Prepare the Repository

Ensure all project files are in place:
```bash
ls -la
# Should see: app/, terraform/, scripts/, requirements.txt, README.md
```

### Step 2: Initialize Terraform

Navigate to the terraform directory and initialize:

```bash
cd terraform
terraform init
```

This downloads the AWS provider and prepares the working directory.

### Step 3: Review the Deployment Plan

Preview the resources that will be created:

```bash
terraform plan
```

Review the output to ensure:
- VPC and networking resources
- Security groups with correct port configurations
- EC2 g6.xlarge instance
- Application Load Balancer with target groups
- IAM roles and instance profile

### Step 4: Apply Terraform Configuration

Deploy the infrastructure:

```bash
terraform apply
```

Type `yes` when prompted to confirm.

**Expected Deployment Time**: 5-10 minutes

The deployment process:
1. Creates VPC and networking (1-2 min)
2. Provisions security groups and IAM roles (1 min)
3. Launches EC2 instance (2-3 min)
4. Creates and configures ALB (2-3 min)
5. Runs user data script to install dependencies (5-10 min in background)

### Step 5: Retrieve ALB DNS Name

After successful deployment, get the ALB DNS name:

```bash
terraform output alb_dns_name
```

Example output:
```
deepseek-ocr-alb-1234567890.us-west-2.elb.amazonaws.com
```

Save this DNS name - you'll use it to access both services.

### Step 6: Wait for Services to Start

The EC2 instance needs additional time to:
- Install NVIDIA drivers and CUDA toolkit
- Install Python dependencies
- Download DeepSeek-OCR model weights (~10GB)
- Start both services

**Total initialization time**: 15-20 minutes after `terraform apply` completes

Monitor progress using SSM (see Troubleshooting section below).

## Usage

### Accessing the Web Interface

Open your browser and navigate to:

```
http://<alb-dns>:8501
```

Example:
```
http://deepseek-ocr-alb-1234567890.us-west-2.elb.amazonaws.com:8501
```

**Using the Interface**:
1. Upload an image (PNG, JPG, or JPEG)
2. Select model size: Tiny, Small, Base, Large, or Gundam
3. Select task type:
   - **Free OCR**: Extract all text from the image
   - **Convert to Markdown**: Convert document to markdown format
   - **Parse Figure**: Extract structured data from charts/figures
   - **Locate Object**: Find specific text (requires reference text input)
4. Click "Process Image"
5. View results: extracted text and annotated image with bounding boxes

### Using the API

The API is OpenAI-compatible and accessible at:

```
http://<alb-dns>:8000
```

#### API Endpoints

**1. Health Check**
```bash
curl http://<alb-dns>:8000/health
```

Response:
```json
{
  "status": "healthy",
  "model_loaded": true
}
```

**2. List Models**
```bash
curl http://<alb-dns>:8000/v1/models
```

Response:
```json
{
  "object": "list",
  "data": [
    {
      "id": "deepseek-ocr",
      "object": "model",
      "created": 1234567890,
      "owned_by": "deepseek-ai"
    }
  ]
}
```

**3. Chat Completions (OCR Inference)**

Basic OCR example:
```bash
curl -X POST http://<alb-dns>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ocr",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Free OCR."},
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            }
          }
        ]
      }
    ],
    "temperature": 0.0,
    "max_tokens": 4096
  }'
```

With custom parameters:
```bash
curl -X POST http://<alb-dns>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ocr",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Convert to markdown."},
          {
            "type": "image_url",
            "image_url": {"url": "data:image/png;base64,..."}
          }
        ]
      }
    ],
    "extra_body": {
      "model_size": "Gundam",
      "task_type": "markdown"
    }
  }'
```

#### API Parameters

**Model Sizes**:
- `Tiny`: Fastest, lower accuracy (512x512)
- `Small`: Fast, good accuracy (640x640)
- `Base`: Balanced (1024x1024)
- `Large`: High accuracy, slower (1280x1280)
- `Gundam`: Best quality with crop mode (1024 base, 640 crops)

**Task Types**:
- `free_ocr`: Extract all text
- `markdown`: Convert document to markdown
- `parse_figure`: Parse charts and figures
- `locate`: Find specific text (requires `ref_text` parameter)

**Example Response**:
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "deepseek-ocr",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Extracted text from the image..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 150,
    "completion_tokens": 75,
    "total_tokens": 225
  }
}
```

### Python Client Example

```python
import requests
import base64
from PIL import Image
import io

# Load and encode image
with open("document.png", "rb") as f:
    img_b64 = base64.b64encode(f.read()).decode()

# Make API request
response = requests.post(
    "http://<alb-dns>:8000/v1/chat/completions",
    json={
        "model": "deepseek-ocr",
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Free OCR."},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{img_b64}"
                        }
                    }
                ]
            }
        ],
        "extra_body": {
            "model_size": "Gundam",
            "task_type": "free_ocr"
        }
    },
    timeout=60
)

# Extract result
result = response.json()
text = result["choices"][0]["message"]["content"]
print(text)
```

## SSM Access and Troubleshooting

### Connecting via AWS Systems Manager

Connect to the EC2 instance without SSH:

```bash
# Get instance ID from Terraform output
terraform output instance_id

# Start SSM session
aws ssm start-session --target <instance-id>
```

Example:
```bash
aws ssm start-session --target i-0123456789abcdef0
```

### Checking Service Status

Once connected via SSM:

```bash
# Check both services
sudo systemctl status deepseek-api
sudo systemctl status deepseek-frontend

# View service logs
sudo journalctl -u deepseek-api -f
sudo journalctl -u deepseek-frontend -f

# Check if services are listening
sudo netstat -tlnp | grep -E '8000|8501'
```

### Monitoring GPU and Memory

```bash
# GPU utilization and memory
nvidia-smi

# Continuous monitoring (updates every 2 seconds)
watch -n 2 nvidia-smi

# System memory
free -h

# Disk usage
df -h
```

### Common Issues and Solutions

#### 1. Services Not Starting

**Symptom**: ALB health checks failing, services not accessible

**Check**:
```bash
# View user data execution log
sudo cat /var/log/cloud-init-output.log

# Check service status
sudo systemctl status deepseek-api
sudo systemctl status deepseek-frontend
```

**Solution**:
```bash
# Restart services
sudo systemctl restart deepseek-api
sudo systemctl restart deepseek-frontend

# If model download failed, run setup script manually
cd /home/ubuntu/deepseek-ocr
sudo bash scripts/setup_app.sh
```

#### 2. Model Loading Errors

**Symptom**: API returns 503 errors, logs show model loading failures

**Check**:
```bash
# Check available GPU memory
nvidia-smi

# Check model files
ls -lh /home/ubuntu/.cache/huggingface/hub/
```

**Solution**:
```bash
# Clear cache and re-download
rm -rf /home/ubuntu/.cache/huggingface/hub/models--deepseek-ai--DeepSeek-OCR
sudo systemctl restart deepseek-api
```

#### 3. Out of Memory Errors

**Symptom**: Inference fails with CUDA out of memory errors

**Check**:
```bash
nvidia-smi
```

**Solution**:
- Use smaller model size (Tiny or Small)
- Reduce image resolution
- Restart API service to clear GPU memory:
```bash
sudo systemctl restart deepseek-api
```

#### 4. ALB Health Checks Failing

**Symptom**: Target groups show unhealthy status in AWS console

**Check**:
```bash
# Test health endpoints locally
curl http://localhost:8000/health
curl http://localhost:8501/

# Check security groups
aws ec2 describe-security-groups --region us-west-2
```

**Solution**:
- Ensure services are running
- Verify security group rules allow ALB to reach EC2 on ports 8000 and 8501
- Wait for model to finish loading (can take 10-15 minutes)

#### 5. Slow Inference

**Symptom**: API requests timeout or take very long

**Check**:
```bash
# Monitor GPU during inference
nvidia-smi -l 1

# Check system load
top
```

**Solution**:
- Use smaller model size
- Reduce image resolution
- Ensure Flash Attention 2 is properly installed
- Check for CPU bottlenecks

### Viewing Application Logs

```bash
# API server logs (last 100 lines)
sudo journalctl -u deepseek-api -n 100

# Frontend logs (last 100 lines)
sudo journalctl -u deepseek-frontend -n 100

# Follow logs in real-time
sudo journalctl -u deepseek-api -f
sudo journalctl -u deepseek-frontend -f

# System logs
sudo tail -f /var/log/syslog
```

### Health Check Script

Run the included health check script:

```bash
cd /home/ubuntu/deepseek-ocr
bash scripts/health_check.sh
```

This verifies:
- API service is responding
- Frontend service is responding
- Model is loaded
- GPU is accessible

## Fast Redeploy (Updated Configuration)

When you need to deploy an updated version quickly without waiting for full resource destruction:

```bash
./scripts/fast_redeploy.sh
```

This script:
1. Removes the EC2 instance from Terraform state (makes it an orphan)
2. Deregisters instance from ALB target groups
3. Terminates the old instance in the background
4. Immediately deploys a new instance with updated configuration

**Benefits**:
- No waiting for full destruction (saves 5-10 minutes)
- New instance starts immediately
- Old instance terminates asynchronously
- Ideal for iterative development and testing

**Use Cases**:
- Testing user_data script changes
- Updating application code
- Changing instance configuration
- Quick rollback to previous version

## Cleanup

### Fast Cleanup (Recommended for Redeploy)

Use the fast redeploy script to quickly replace the instance:

```bash
./scripts/fast_redeploy.sh
```

### Full Cleanup (Complete Destruction)

To destroy all resources and avoid ongoing charges:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. This will:
- Terminate the EC2 instance
- Delete the Application Load Balancer
- Remove all networking resources
- Delete security groups and IAM roles

**Note**: This action is irreversible. Ensure you've backed up any data before destroying.

## Cost Estimation

Approximate hourly costs (us-west-2 region):
- EC2 g6.xlarge: $0.70/hour
- Application Load Balancer: $0.0225/hour + $0.008/LCU-hour
- EBS gp3 100GB: $0.08/month (~$0.0001/hour)
- Data transfer: Variable based on usage

**Total estimated cost**: ~$0.75-$1.00/hour

## Architecture Diagram

```
Internet
    ↓
Application Load Balancer
    ├── Listener :8501 → Frontend Target Group
    └── Listener :8000 → API Target Group
            ↓
    EC2 g6.xlarge Instance
        ├── Streamlit Frontend :8501
        ├── FastAPI Server :8000
        └── DeepSeek-OCR Model (GPU)
```

## Support and Resources

- **DeepSeek-OCR Model**: https://huggingface.co/deepseek-ai/DeepSeek-OCR
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **AWS Systems Manager**: https://docs.aws.amazon.com/systems-manager/
- **FastAPI Documentation**: https://fastapi.tiangolo.com/
- **Streamlit Documentation**: https://docs.streamlit.io/

## License

This deployment configuration is provided as-is. Please refer to the DeepSeek-OCR model license for model usage terms.

## Current Deployment Status

**Instance ID**: `i-0f3418b7b8b679874`  
**Status**: ✅ Healthy and Operational  
**Last Updated**: October 30, 2025

### Endpoints
- **API Health**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/health
- **API Docs**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/docs
- **Frontend**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8501

### Recent Fixes
1. **Model Returns "None"**: Fixed flash-attn installation by adding CUDA development tools and proper build dependencies
2. **SSM Access Issues**: Added bash installation in user_data for SSM agent compatibility
3. **Flash Attention**: Properly configured flash-attn 2.7.3 with PyTorch 2.6.0 and CUDA 12.6
4. **Model API**: Updated to use correct `infer()` method instead of `chat()` method
5. **Fast Redeploy**: Added script to quickly replace instances without waiting for full destruction

### Known Requirements
- **Flash Attention 2**: Critical for DeepSeek-OCR performance and functionality
- **CUDA Toolkit**: Required for flash-attn compilation (installed during setup)
- **PyTorch 2.6.0**: Specific version required for compatibility
- **Transformers 4.46.3**: Pinned version for model loading
- **Build Time**: flash-attn compilation takes 10-15 minutes during first boot

### Connect to Instance
```bash
aws ssm start-session --target i-0f3418b7b8b679874 --region us-west-2
```
