#!/usr/bin/env python3
"""
Test script for DeepSeek-OCR API endpoint
Tests with the image at test/img/ss1.png
"""

import requests
import base64
import json
import sys
from pathlib import Path

# Configuration
ALB_DNS = "deepseek-ocr-alb-1839990555.us-west-2.elb.amazonaws.com"
API_URL = f"http://{ALB_DNS}:8000"
TEST_IMAGE = "test/img/ss1.png"

def test_health():
    """Test health endpoint"""
    print("1. Testing health endpoint...")
    try:
        response = requests.get(f"{API_URL}/health", timeout=10)
        response.raise_for_status()
        data = response.json()
        print(f"   ✓ Health check passed: {data}")
        return True
    except Exception as e:
        print(f"   ✗ Health check failed: {e}")
        return False

def test_models():
    """Test models endpoint"""
    print("\n2. Testing models endpoint...")
    try:
        response = requests.get(f"{API_URL}/v1/models", timeout=10)
        response.raise_for_status()
        data = response.json()
        print(f"   ✓ Models endpoint: {json.dumps(data, indent=2)}")
        return True
    except Exception as e:
        print(f"   ✗ Models endpoint failed: {e}")
        return False

def test_ocr():
    """Test OCR with test image"""
    print("\n3. Testing OCR inference...")
    
    # Check if test image exists
    image_path = Path(TEST_IMAGE)
    if not image_path.exists():
        print(f"   ✗ Test image not found: {TEST_IMAGE}")
        return False
    
    # Read and encode image
    print(f"   Loading image: {TEST_IMAGE}")
    with open(image_path, "rb") as f:
        img_data = f.read()
        img_b64 = base64.b64encode(img_data).decode()
    
    # Prepare request
    payload = {
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
        },
        "temperature": 0.0,
        "max_tokens": 4096
    }
    
    print("   Sending OCR request...")
    try:
        response = requests.post(
            f"{API_URL}/v1/chat/completions",
            json=payload,
            timeout=120  # OCR can take time
        )
        response.raise_for_status()
        data = response.json()
        
        # Extract result
        if "choices" in data and len(data["choices"]) > 0:
            result_text = data["choices"][0]["message"]["content"]
            print(f"   ✓ OCR successful!")
            print(f"\n   Extracted text:")
            print(f"   {'-' * 60}")
            print(f"   {result_text}")
            print(f"   {'-' * 60}")
            
            # Check if result is not "None"
            if result_text and result_text.strip().lower() != "none":
                print(f"\n   ✓ Result is valid (not 'None')")
                return True
            else:
                print(f"\n   ✗ Result is 'None' - model not working correctly")
                return False
        else:
            print(f"   ✗ Unexpected response format: {json.dumps(data, indent=2)}")
            return False
            
    except requests.exceptions.Timeout:
        print(f"   ✗ Request timed out (model may still be loading)")
        return False
    except Exception as e:
        print(f"   ✗ OCR request failed: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"   Response: {e.response.text}")
        return False

def main():
    """Run all tests"""
    print("=" * 70)
    print("DeepSeek-OCR API Test Suite")
    print("=" * 70)
    print(f"API URL: {API_URL}")
    print(f"Test Image: {TEST_IMAGE}")
    print()
    
    results = []
    
    # Run tests
    results.append(("Health Check", test_health()))
    results.append(("Models Endpoint", test_models()))
    results.append(("OCR Inference", test_ocr()))
    
    # Summary
    print("\n" + "=" * 70)
    print("Test Summary")
    print("=" * 70)
    
    for test_name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{test_name:.<50} {status}")
    
    all_passed = all(result[1] for result in results)
    
    print("=" * 70)
    if all_passed:
        print("✓ All tests passed!")
        return 0
    else:
        print("✗ Some tests failed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
