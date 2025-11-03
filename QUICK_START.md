# Quick Start Guide - First Time Deployment

This guide will help you deploy DeepSeek-OCR to AWS in under 5 minutes (plus 15-20 minutes for automatic initialization).

## Prerequisites

Before running the deployment script, ensure you have:

1. **AWS CLI** installed and configured
   ```bash
   aws configure
   # Enter your AWS Access Key, Secret Key, and set region to us-west-2
   ```

2. **Terraform** installed (v1.0+)
   ```bash
   terraform version
   ```

3. **AWS Permissions** - Your AWS user/role needs permissions for:
   - EC2, VPC, ELB, IAM, S3, Systems Manager

## One-Command Deployment

Run the automated deployment script:

```bash
./scripts/first_time_deploy.sh
```

## What the Script Does

The script automatically:

1. ✅ Verifies all prerequisites (Terraform, AWS CLI, credentials)
2. ✅ Checks project structure and required files
3. ✅ Creates S3 bucket for deployment assets
4. ✅ Uploads application code to S3
5. ✅ Initializes Terraform
6. ✅ Validates Terraform configuration
7. ✅ Shows deployment plan for review
8. ✅ Deploys infrastructure (after your confirmation)
9. ✅ Displays endpoints and monitoring commands

**Total time:** ~5 minutes for deployment + 15-20 minutes for automatic initialization

## After Deployment

### Monitor Initialization Progress

```bash
./scripts/monitor_new_instance.sh
```

This shows real-time progress of:
- CUDA installation
- Python dependencies
- Flash Attention compilation
- Model download
- Service startup

### Access Your Deployment

Once initialization completes (15-20 minutes), access:

- **Web Interface:** `http://<alb-dns>:8501`
- **API Endpoint:** `http://<alb-dns>:8000`
- **API Documentation:** `http://<alb-dns>:8000/docs`
- **Health Check:** `http://<alb-dns>:8000/health`

Replace `<alb-dns>` with the ALB DNS name shown after deployment.

### Test the Deployment

```bash
python3 scripts/test_ocr_endpoint.py
```

### Connect to Instance

```bash
# Get instance ID from deployment output, then:
aws ssm start-session --target <instance-id> --region us-west-2
```

## Troubleshooting

### Script Fails at Prerequisites

- **Terraform not found:** Install from https://www.terraform.io/downloads
- **AWS CLI not found:** Install from https://aws.amazon.com/cli/
- **AWS credentials invalid:** Run `aws configure` and enter valid credentials

### Script Fails at S3 Upload

- Check AWS permissions include S3 access
- Verify region is set correctly (us-west-2)

### Script Fails at Terraform Apply

- Review the error message in the output
- Check AWS service quotas (EC2 instances, VPCs, etc.)
- Verify IAM permissions are sufficient

### Services Not Ready After 20 Minutes

Connect via SSM and check logs:
```bash
aws ssm start-session --target <instance-id> --region us-west-2

# Once connected:
sudo tail -f /var/log/user-data.log
sudo systemctl status deepseek-api
sudo journalctl -u deepseek-api -f
```

## Updating Code

After initial deployment, use the fast redeploy script:

```bash
./scripts/redeploy.sh
```

This updates code and redeploys in ~3 minutes (vs 20+ minutes for full redeployment).

## Cleanup

To destroy all resources and stop charges:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted.

## Cost Estimate

- **EC2 g6.xlarge:** ~$0.70/hour
- **Application Load Balancer:** ~$0.05/hour
- **Total:** ~$0.75-$1.00/hour

**Remember to destroy resources when not in use!**

## Support

For detailed information, see:
- `README.md` - Complete documentation
- `scripts/README.md` - Script documentation
- `DEPLOYMENT_SUCCESS.md` - Deployment notes

## Quick Command Reference

```bash
# Deploy for first time
./scripts/first_time_deploy.sh

# Monitor initialization
./scripts/monitor_new_instance.sh

# Test deployment
python3 scripts/test_ocr_endpoint.py

# Redeploy with code changes
./scripts/redeploy.sh

# Connect to instance
aws ssm start-session --target <instance-id> --region us-west-2

# Destroy everything
cd terraform && terraform destroy
```
