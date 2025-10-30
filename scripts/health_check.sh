#!/bin/bash

# Health check script for DeepSeek-OCR services
# Verifies that both API and frontend services are running and responding

set -e

echo "=========================================="
echo "DeepSeek-OCR Health Check"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall health status
OVERALL_STATUS=0

# Check if API service is running
echo "1. Checking API service status..."
if systemctl is-active --quiet deepseek-api; then
    echo -e "${GREEN}✓${NC} API service is running"
else
    echo -e "${RED}✗${NC} API service is not running"
    OVERALL_STATUS=1
fi

# Check if frontend service is running
echo ""
echo "2. Checking frontend service status..."
if systemctl is-active --quiet deepseek-frontend; then
    echo -e "${GREEN}✓${NC} Frontend service is running"
else
    echo -e "${RED}✗${NC} Frontend service is not running"
    OVERALL_STATUS=1
fi

# Check if API responds on port 8000
echo ""
echo "3. Checking API endpoint (port 8000)..."
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health || echo "000")
if [ "$API_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC} API endpoint is responding (HTTP $API_RESPONSE)"
    
    # Check if model is loaded
    MODEL_STATUS=$(curl -s http://localhost:8000/health | grep -o '"model_loaded":[^,}]*' | cut -d':' -f2 || echo "unknown")
    if [ "$MODEL_STATUS" = "true" ]; then
        echo -e "${GREEN}✓${NC} Model is loaded successfully"
    else
        echo -e "${YELLOW}⚠${NC} Model load status: $MODEL_STATUS"
    fi
else
    echo -e "${RED}✗${NC} API endpoint is not responding (HTTP $API_RESPONSE)"
    OVERALL_STATUS=1
fi

# Check if frontend responds on port 8501
echo ""
echo "4. Checking frontend endpoint (port 8501)..."
FRONTEND_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8501 || echo "000")
if [ "$FRONTEND_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC} Frontend endpoint is responding (HTTP $FRONTEND_RESPONSE)"
else
    echo -e "${RED}✗${NC} Frontend endpoint is not responding (HTTP $FRONTEND_RESPONSE)"
    OVERALL_STATUS=1
fi

# Check GPU availability
echo ""
echo "5. Checking GPU availability..."
if command -v nvidia-smi &> /dev/null; then
    GPU_STATUS=$(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo "error")
    if [ "$GPU_STATUS" != "error" ]; then
        echo -e "${GREEN}✓${NC} GPU is available"
        echo "   $GPU_STATUS"
    else
        echo -e "${RED}✗${NC} GPU query failed"
        OVERALL_STATUS=1
    fi
else
    echo -e "${RED}✗${NC} nvidia-smi not found"
    OVERALL_STATUS=1
fi

# Check disk space
echo ""
echo "6. Checking disk space..."
DISK_USAGE=$(df -h /opt/deepseek-ocr | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "${GREEN}✓${NC} Disk usage is healthy ($DISK_USAGE%)"
else
    echo -e "${YELLOW}⚠${NC} Disk usage is high ($DISK_USAGE%)"
fi

# Check memory usage
echo ""
echo "7. Checking memory usage..."
MEMORY_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
if [ "$MEMORY_USAGE" -lt 90 ]; then
    echo -e "${GREEN}✓${NC} Memory usage is healthy ($MEMORY_USAGE%)"
else
    echo -e "${YELLOW}⚠${NC} Memory usage is high ($MEMORY_USAGE%)"
fi

# Summary
echo ""
echo "=========================================="
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}Overall Status: HEALTHY${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}Overall Status: UNHEALTHY${NC}"
    echo "=========================================="
    echo ""
    echo "Troubleshooting tips:"
    echo "  - Check service logs: journalctl -u deepseek-api -n 50"
    echo "  - Check service logs: journalctl -u deepseek-frontend -n 50"
    echo "  - Restart services: sudo systemctl restart deepseek-api deepseek-frontend"
    exit 1
fi
