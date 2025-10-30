"""
FastAPI OpenAI-Compatible API Server for DeepSeek-OCR

Provides REST API endpoints compatible with OpenAI API specification.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any, Literal
import time
import uuid
import torch
from PIL import Image

from app.model_engine import (
    ModelManager,
    run_inference,
    decode_base64_image,
    validate_image_format,
    encode_image_to_base64
)


app = FastAPI(
    title="DeepSeek-OCR API",
    description="OpenAI-compatible API for DeepSeek-OCR model",
    version="1.0.0"
)

# Enable CORS for all origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Pydantic models for request/response
class MessageContent(BaseModel):
    type: str
    text: Optional[str] = None
    image_url: Optional[Dict[str, str]] = None


class Message(BaseModel):
    role: str
    content: List[MessageContent] | str


class ChatCompletionRequest(BaseModel):
    model: str = "deepseek-ocr"
    messages: List[Message]
    temperature: float = 0.0
    max_tokens: int = 4096
    extra_body: Optional[Dict[str, Any]] = None


class Choice(BaseModel):
    index: int
    message: Message
    finish_reason: str


class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[Choice]
    usage: Usage


class ModelInfo(BaseModel):
    id: str
    object: str = "model"
    created: int
    owned_by: str = "deepseek-ai"


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    gpu_available: bool


@app.on_event("startup")
async def startup_event():
    """Pre-load model on startup."""
    try:
        print("Starting API server...")
        print("Pre-loading DeepSeek-OCR model...")
        ModelManager.get_model()
        print("Model loaded successfully!")
    except Exception as e:
        print(f"Warning: Failed to pre-load model: {str(e)}")
        print("Model will be loaded on first request")


@app.on_event("shutdown")
async def shutdown_event():
    """Graceful shutdown - clear GPU cache and cleanup resources."""
    try:
        print("Shutting down API server...")
        print("Clearing GPU cache...")
        torch.cuda.empty_cache()
        print("Shutdown complete!")
    except Exception as e:
        print(f"Warning during shutdown: {str(e)}")


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint for ALB.
    
    Returns service status and model loaded state.
    """
    return HealthResponse(
        status="healthy",
        model_loaded=ModelManager.is_loaded(),
        gpu_available=torch.cuda.is_available()
    )


@app.get("/models")
async def list_models():
    """
    List available models (OpenAI-compatible endpoint).
    """
    return {
        "object": "list",
        "data": [
            ModelInfo(
                id="deepseek-ocr",
                created=int(time.time()),
                owned_by="deepseek-ai"
            )
        ]
    }



@app.post("/v1/chat/completions", response_model=ChatCompletionResponse)
async def chat_completions(request: ChatCompletionRequest):
    """
    OpenAI-compatible chat completions endpoint.
    
    Processes OCR requests with image input and returns extracted text.
    """
    try:
        # Extract image and parameters from request
        image = None
        prompt_text = ""
        
        # Parse messages to extract image and text
        for message in request.messages:
            if message.role == "user":
                if isinstance(message.content, list):
                    for content in message.content:
                        if content.type == "text" and content.text:
                            prompt_text = content.text
                        elif content.type == "image_url" and content.image_url:
                            # Extract image from URL or base64
                            image_url = content.image_url.get("url", "")
                            if image_url.startswith("data:image"):
                                image = decode_base64_image(image_url)
                            else:
                                raise HTTPException(
                                    status_code=400,
                                    detail="Only base64 encoded images are supported"
                                )
        
        if image is None:
            raise HTTPException(
                status_code=400,
                detail="No image provided in request"
            )
        
        # Extract task parameters from extra_body
        model_size = "Gundam"
        task_type = "free_ocr"
        ref_text = None
        
        if request.extra_body:
            model_size = request.extra_body.get("model_size", "Gundam")
            task_type = request.extra_body.get("task_type", "free_ocr")
            ref_text = request.extra_body.get("ref_text")
        
        # Run inference
        try:
            result = run_inference(
                image=image,
                model_size=model_size,
                task_type=task_type,
                ref_text=ref_text
            )
        except torch.cuda.OutOfMemoryError:
            raise HTTPException(
                status_code=507,
                detail="GPU memory insufficient"
            )
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Inference failed: {str(e)}"
            )
        
        # Format response
        response_text = result["text"]
        
        # Include annotated image if available
        annotated_image_b64 = None
        if result.get("annotated_image"):
            annotated_image_b64 = encode_image_to_base64(result["annotated_image"])
        
        # Create response
        completion_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
        
        # Build response content
        response_content = response_text
        
        response = ChatCompletionResponse(
            id=completion_id,
            created=int(time.time()),
            model=request.model,
            choices=[
                Choice(
                    index=0,
                    message=Message(
                        role="assistant",
                        content=response_content
                    ),
                    finish_reason="stop"
                )
            ],
            usage=Usage(
                prompt_tokens=100,  # Approximate
                completion_tokens=len(response_text.split()),
                total_tokens=100 + len(response_text.split())
            )
        )
        
        # Add annotated image to response if available (as custom field)
        response_dict = response.dict()
        if annotated_image_b64:
            response_dict["annotated_image"] = annotated_image_b64
        
        return response_dict
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )


@app.post("/v1/completions")
async def completions(request: Dict[str, Any]):
    """
    OpenAI-compatible completions endpoint.
    
    Redirects to chat completions for compatibility.
    """
    raise HTTPException(
        status_code=501,
        detail="Use /v1/chat/completions endpoint instead"
    )


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )
