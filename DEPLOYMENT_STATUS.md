# DeepSeek-OCR AWS Deployment Status

## ✅ Deployment Complete

### Instance Information
- **Instance ID**: `i-036a7803994ddcdcb`
- **Instance Type**: `g6.xlarge` (NVIDIA L4 GPU)
- **Region**: `us-west-2`
- **Status**: Running with GPU enabled

### Public Endpoints

#### API Server
- **Health Check**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/health
- **Models List**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/models
- **API Documentation**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/docs
- **Chat Completions**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/v1/chat/completions

#### Frontend
- **Streamlit UI**: http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8501

### Current Status
```json
{
  "status": "healthy",
  "model_loaded": false,
  "gpu_available": true
}
```

- ✅ **GPU Available**: NVIDIA drivers loaded successfully after reboot
- ✅ **Services Running**: Both API and Frontend services are active
- ℹ️ **Model Not Loaded**: Model uses lazy loading - will load on first inference request

### Auto-Start Configuration

Both services are configured to start automatically on every boot:

#### API Service (`deepseek-api.service`)
- **Status**: Enabled and running
- **Auto-start**: Yes (`WantedBy=multi-user.target`)
- **Auto-restart**: Yes (`Restart=always`)
- **Logs**: `/opt/deepseek-ocr/logs/api.log`

#### Frontend Service (`deepseek-frontend.service`)
- **Status**: Enabled and running
- **Auto-start**: Yes (`WantedBy=multi-user.target`)
- **Auto-restart**: Yes (`Restart=always`)
- **Depends on**: API service must start first
- **Logs**: `/opt/deepseek-ocr/logs/frontend.log`

### GitHub Repository
- **URL**: https://github.com/CK-vn/deepseek-ocr-streamlit-demo
- **Branch**: main
- **Visibility**: Public

### Deployment Process

The deployment uses:
1. **Terraform** for infrastructure provisioning
2. **User Data Script** for automated setup on instance launch
3. **Systemd Services** for process management and auto-start
4. **Application Load Balancer** for public access

### Testing the Model

To test the OCR model, make a POST request to the chat completions endpoint:

```bash
curl -X POST http://deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ocr",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Extract text from this image"
          },
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/png;base64,<YOUR_BASE64_IMAGE>"
            }
          }
        ]
      }
    ]
  }'
```

**Note**: The first request will take several minutes as it downloads and loads the model (~10GB). Subsequent requests will be much faster.

### Reboot Behavior

✅ **Confirmed**: Services automatically start after reboot
- Instance was rebooted to enable GPU drivers
- Both services started automatically without manual intervention
- GPU is now available and functional

### Future Reboots

The system is configured to:
1. ✅ Load NVIDIA drivers automatically
2. ✅ Start API service automatically
3. ✅ Start Frontend service automatically (after API)
4. ✅ Restart services if they crash
5. ✅ Use GPU for inference when available

### Management Commands

```bash
# Check service status
systemctl status deepseek-api.service
systemctl status deepseek-frontend.service

# View logs
tail -f /opt/deepseek-ocr/logs/api.log
tail -f /opt/deepseek-ocr/logs/frontend.log

# Restart services
systemctl restart deepseek-api.service
systemctl restart deepseek-frontend.service

# Check GPU status
nvidia-smi

# Connect via SSM
aws ssm start-session --target i-036a7803994ddcdcb --region us-west-2
```

### Known Issues

- SSM agent has PATH issues after reboot (doesn't affect service operation)
- Model lazy loading means first inference request is slow
- GPU memory: ~24GB available on L4
- User data script may take 15-20 minutes to complete full initialization

### Manual Dependency Installation (if needed)

If the automated setup doesn't complete or you encounter missing dependencies error, you can manually install them:

```bash
# Connect to instance
aws ssm start-session --target <INSTANCE_ID> --region us-west-2

# Install missing dependencies
sudo -u ubuntu /opt/deepseek-ocr/venv/bin/pip install addict matplotlib torchvision

# Restart services
sudo systemctl restart deepseek-api.service
sudo systemctl restart deepseek-frontend.service
```

### Next Steps

1. Test OCR inference with sample images
2. Monitor GPU memory usage during inference
3. Set up CloudWatch alarms for service health
4. Consider adding auto-scaling if needed
5. Implement model caching for faster cold starts

---

**Deployment Date**: October 30, 2025  
**Last Updated**: After GPU enablement reboot
