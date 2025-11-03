# DeepSeek-OCR Deployment Scripts

Essential scripts for deploying and managing the DeepSeek-OCR instance.

## Scripts Overview

### 1. `redeploy.sh` - Fast Redeployment
**Purpose:** Quickly redeploy instance with updated code

**Usage:**
```bash
./scripts/redeploy.sh
```

**What it does:**
1. Uploads updated code to S3
2. Removes current instance from Terraform state
3. Terminates old instance (async)
4. Deploys new instance with latest code

**When to use:**
- After making code changes
- After updating dependencies
- When you need a fresh instance quickly

**Time:** ~3 minutes (vs 15-20 minutes for full destroy/apply)

---

### 2. `monitor_new_instance.sh` - Monitor Initialization
**Purpose:** Monitor instance initialization progress

**Usage:**
```bash
./scripts/monitor_new_instance.sh
```

**What it does:**
- Automatically gets instance ID from Terraform
- Tails user-data log every 20 seconds
- Shows when initialization completes
- Displays service status

**When to use:**
- After running `redeploy.sh`
- After `terraform apply`
- To check if services are ready

**Expected time:** 15-20 minutes for full initialization

---

### 3. `test_ocr_endpoint.py` - Test Endpoints
**Purpose:** Comprehensive API and OCR testing

**Usage:**
```bash
python3 scripts/test_ocr_endpoint.py
```

**What it tests:**
- ✓ Health check endpoint
- ✓ Models list endpoint
- ✓ OCR inference with test image
- ✓ Result validation

**When to use:**
- After deployment completes
- To verify services are working
- For troubleshooting

**Requirements:**
- Test image at `test/img/ss1.png`
- Python 3 with `requests` and `Pillow`

---

### 4. `setup_app.sh` - Manual Setup
**Purpose:** Manual application setup (used by user_data.sh)

**Usage:**
```bash
# On the EC2 instance
sudo bash /opt/deepseek-ocr/scripts/setup_app.sh
```

**What it does:**
- Downloads code from S3
- Installs Python dependencies
- Sets up directory structure

**When to use:**
- Manual troubleshooting on instance
- Re-running setup after failures
- Testing setup process

**Note:** This is automatically run by `user_data.sh` during instance launch

---

## Quick Start

### Deploy New Instance
```bash
# First time deployment
cd terraform
terraform init
terraform apply

# Monitor initialization
./scripts/monitor_new_instance.sh

# Test when ready
./scripts/test_ocr_endpoint.py
```

### Update and Redeploy
```bash
# Make code changes to app/*.py or requirements.txt

# Fast redeploy
./scripts/redeploy.sh

# Monitor
./scripts/monitor_new_instance.sh

# Test
./scripts/test_ocr_endpoint.py
```

---

## Troubleshooting

### Services Not Starting
```bash
# Connect to instance
INSTANCE_ID=$(terraform -chdir=terraform output -raw ec2_instance_id)
aws ssm start-session --target ${INSTANCE_ID} --region us-west-2

# Check logs
sudo journalctl -u deepseek-api -n 100
sudo journalctl -u deepseek-frontend -n 100
sudo tail -100 /var/log/user-data.log
```

### Redeploy Fails
```bash
# Check Terraform state
cd terraform
terraform state list

# If instance stuck in state, manually remove
terraform state rm aws_lb_target_group_attachment.api
terraform state rm aws_lb_target_group_attachment.frontend

# Try again
cd ..
./scripts/redeploy.sh
```

### Test Fails
```bash
# Check ALB DNS
terraform -chdir=terraform output alb_dns_name

# Check instance status
aws ec2 describe-instances \
    --instance-ids $(terraform -chdir=terraform output -raw ec2_instance_id) \
    --region us-west-2 \
    --query 'Reservations[0].Instances[0].State.Name'

# Check target health
aws elbv2 describe-target-health \
    --target-group-arn $(terraform -chdir=terraform output -raw api_target_group_arn) \
    --region us-west-2
```

---

## Notes

- All scripts assume `us-west-2` region
- S3 bucket name: `deepseek-ocr-deployment-assets`
- Instance initialization takes 15-20 minutes
- Flash Attention compilation is the longest step (10-15 min)
- Services auto-start after initialization
