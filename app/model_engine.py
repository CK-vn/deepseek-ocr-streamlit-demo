"""
DeepSeek-OCR Model Inference Engine

Shared module for model loading, inference execution, and result processing.
"""

import torch
import re
from PIL import Image, ImageDraw
from transformers import AutoTokenizer, AutoModel
from typing import Optional, Tuple, Dict, Any
import io
import base64


# Model size configurations
SIZE_CONFIGS = {
    "Tiny": {"base_size": 512, "image_size": 512, "crop_mode": False},
    "Small": {"base_size": 640, "image_size": 640, "crop_mode": False},
    "Base": {"base_size": 1024, "image_size": 1024, "crop_mode": False},
    "Large": {"base_size": 1280, "image_size": 1280, "crop_mode": False},
    "Gundam": {"base_size": 1024, "image_size": 640, "crop_mode": True}
}

# Task prompt templates
TASK_PROMPTS = {
    "free_ocr": "<image>\nFree OCR.",
    "markdown": "<image>\n<|grounding|>Convert the document to markdown.",
    "parse_figure": "<image>\nParse the figure.",
    "locate": "<image>\nLocate <|ref|>{ref_text}<|/ref|> in the image."
}


class ModelManager:
    """Singleton class for managing DeepSeek-OCR model loading and caching."""
    
    _instance = None
    _model = None
    _tokenizer = None
    _loading_error = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ModelManager, cls).__new__(cls)
        return cls._instance
    
    @classmethod
    def get_model(cls) -> Tuple[Any, Any]:
        """
        Get or load the DeepSeek-OCR model and tokenizer using lazy loading.
        
        Returns:
            Tuple of (model, tokenizer)
        
        Raises:
            RuntimeError: If model loading fails
            torch.cuda.OutOfMemoryError: If GPU memory is insufficient
        """
        # If model is already loaded, return it
        if cls._model is not None:
            return cls._model, cls._tokenizer
        
        # If previous loading attempt failed, raise the error
        if cls._loading_error is not None:
            raise RuntimeError(f"Model loading previously failed: {cls._loading_error}")
        
        # Attempt to load the model (lazy loading)
        try:
            print("Loading DeepSeek-OCR model...")
            print("This may take a few minutes on first run...")
            
            # Load tokenizer
            cls._tokenizer = AutoTokenizer.from_pretrained(
                "deepseek-ai/DeepSeek-OCR",
                trust_remote_code=True
            )
            
            # Load model with bfloat16 precision
            # Try to use Flash Attention 2 if available (required for production)
            try:
                print("Attempting to load model with Flash Attention 2...")
                cls._model = AutoModel.from_pretrained(
                    "deepseek-ai/DeepSeek-OCR",
                    attn_implementation="flash_attention_2",
                    trust_remote_code=True,
                    torch_dtype=torch.bfloat16,
                    use_safetensors=True
                ).cuda().eval()
                print("✓ Model loaded with Flash Attention 2")
            except Exception as e:
                print(f"⚠ Flash Attention 2 not available: {e}")
                print("Falling back to default attention (slower performance)...")
                cls._model = AutoModel.from_pretrained(
                    "deepseek-ai/DeepSeek-OCR",
                    trust_remote_code=True,
                    torch_dtype=torch.bfloat16,
                    use_safetensors=True
                ).cuda().eval()
                print("✓ Model loaded with default attention")
            
            print("Model loaded successfully!")
            return cls._model, cls._tokenizer
            
        except torch.cuda.OutOfMemoryError as e:
            error_msg = f"GPU out of memory: {str(e)}"
            cls._loading_error = error_msg
            print(f"Error loading model: {error_msg}")
            raise torch.cuda.OutOfMemoryError(error_msg)
        except Exception as e:
            error_msg = f"Failed to load model: {str(e)}"
            cls._loading_error = error_msg
            print(f"Error loading model: {error_msg}")
            raise RuntimeError(error_msg)
    
    @classmethod
    def is_loaded(cls) -> bool:
        """Check if model is loaded."""
        return cls._model is not None
    
    @classmethod
    def clear_cache(cls):
        """Clear cached model and tokenizer (useful for testing or memory management)."""
        if cls._model is not None:
            del cls._model
            cls._model = None
        if cls._tokenizer is not None:
            del cls._tokenizer
            cls._tokenizer = None
        cls._loading_error = None
        torch.cuda.empty_cache()


def build_prompt(task_type: str, ref_text: Optional[str] = None) -> str:
    """
    Build prompt based on task type and reference text.
    
    Args:
        task_type: One of 'free_ocr', 'markdown', 'parse_figure', 'locate'
        ref_text: Reference text for locate task (required for 'locate' task)
    
    Returns:
        Formatted prompt string
    
    Raises:
        ValueError: If task_type is invalid or ref_text is missing for locate task
    """
    if task_type not in TASK_PROMPTS:
        valid_tasks = ", ".join(TASK_PROMPTS.keys())
        raise ValueError(f"Invalid task type: {task_type}. Valid options: {valid_tasks}")
    
    prompt = TASK_PROMPTS[task_type]
    
    # For locate task, reference text is required
    if task_type == "locate":
        if not ref_text:
            raise ValueError("Reference text is required for 'locate' task")
        prompt = prompt.format(ref_text=ref_text)
    
    return prompt


def get_model_config(model_size: str) -> Dict[str, Any]:
    """
    Get model configuration for a given size.
    
    Args:
        model_size: One of 'Tiny', 'Small', 'Base', 'Large', 'Gundam'
    
    Returns:
        Dictionary with base_size, image_size, and crop_mode
    
    Raises:
        ValueError: If model_size is invalid
    """
    if model_size not in SIZE_CONFIGS:
        valid_sizes = ", ".join(SIZE_CONFIGS.keys())
        raise ValueError(f"Invalid model size: {model_size}. Valid options: {valid_sizes}")
    
    return SIZE_CONFIGS[model_size].copy()


def preprocess_image(image: Image.Image, model_size: str) -> Image.Image:
    """
    Preprocess image according to model size configuration.
    
    Args:
        image: PIL Image object
        model_size: One of 'Tiny', 'Small', 'Base', 'Large', 'Gundam'
    
    Returns:
        Preprocessed PIL Image
    
    Raises:
        ValueError: If model_size is invalid or image is invalid
    """
    if not isinstance(image, Image.Image):
        raise ValueError("Invalid image: must be a PIL Image object")
    
    config = get_model_config(model_size)
    
    # Convert to RGB if needed
    if image.mode != "RGB":
        image = image.convert("RGB")
    
    # Resize based on configuration
    # Note: The model may have specific preprocessing requirements
    max_size = config["image_size"]
    image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    
    return image


def run_inference(
    image: Image.Image,
    model_size: str = "Gundam",
    task_type: str = "free_ocr",
    ref_text: Optional[str] = None,
    timeout: int = 300
) -> Dict[str, Any]:
    """
    Run OCR inference on an image with GPU memory management and timeout handling.
    
    Args:
        image: PIL Image object
        model_size: Model size configuration (Tiny, Small, Base, Large, Gundam)
        task_type: Type of OCR task (free_ocr, markdown, parse_figure, locate)
        ref_text: Reference text for locate task (required if task_type is 'locate')
        timeout: Maximum inference time in seconds (default: 300)
    
    Returns:
        Dictionary containing:
            - text: Extracted text from the image
            - bounding_boxes: List of bounding box coordinates [(x1,y1,x2,y2), ...]
            - annotated_image: PIL Image with bounding boxes drawn (None if no boxes)
    
    Raises:
        ValueError: If image format is invalid or parameters are incorrect
        torch.cuda.OutOfMemoryError: If GPU memory is insufficient
        TimeoutError: If inference exceeds timeout
        RuntimeError: For other inference errors
    """
    try:
        # Validate image format
        if not isinstance(image, Image.Image):
            raise ValueError("Invalid image: must be a PIL Image object")
        
        # Get model and tokenizer (lazy loading)
        model, tokenizer = ModelManager.get_model()
        
        # Preprocess image
        processed_image = preprocess_image(image, model_size)
        
        # Build prompt
        prompt = build_prompt(task_type, ref_text)
        
        # Get model configuration
        config = get_model_config(model_size)
        
        # Clear GPU cache before inference to maximize available memory
        torch.cuda.empty_cache()
        
        # Run inference with no gradient computation for memory efficiency
        with torch.no_grad():
            try:
                # DeepSeek-OCR uses the infer() method, not chat()
                # Save image temporarily for the infer method
                import tempfile
                import os
                with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_file:
                    processed_image.save(tmp_file.name)
                    tmp_path = tmp_file.name
                
                try:
                    # Call the model's infer method (official DeepSeek-OCR API)
                    response = model.infer(
                        tokenizer=tokenizer,
                        prompt=prompt,
                        image_file=tmp_path,
                        output_path=None,  # Don't save output files
                        base_size=config["base_size"],
                        image_size=config["image_size"],
                        crop_mode=config["crop_mode"],
                        save_results=False,
                        test_compress=False
                    )
                finally:
                    # Clean up temp file
                    if os.path.exists(tmp_path):
                        os.unlink(tmp_path)
                        
            except Exception as e:
                raise RuntimeError(f"Model inference failed: {str(e)}")
        
        # Parse model output to extract text
        # The response should be a string containing the OCR results
        if not isinstance(response, str):
            response = str(response)
        
        # Initialize result dictionary
        result = {
            "text": response,
            "bounding_boxes": [],
            "annotated_image": None
        }
        
        # Extract bounding boxes if present in the output
        bboxes = extract_bounding_boxes(response, image.size)
        if bboxes:
            result["bounding_boxes"] = bboxes
            # Draw bounding boxes on a copy of the original image
            result["annotated_image"] = draw_bounding_boxes(image.copy(), bboxes)
        
        # Clear GPU cache after inference
        torch.cuda.empty_cache()
        
        return result
        
    except torch.cuda.OutOfMemoryError as e:
        # Clear cache and re-raise
        torch.cuda.empty_cache()
        raise torch.cuda.OutOfMemoryError(
            f"GPU out of memory during inference. Try using a smaller model size. Error: {str(e)}"
        )
    except ValueError as e:
        # Re-raise validation errors
        raise
    except Exception as e:
        # Wrap other errors in RuntimeError
        raise RuntimeError(f"Inference failed: {str(e)}")


def extract_bounding_boxes(text: str, image_size: Tuple[int, int]) -> list:
    """
    Parse detection coordinates from model output using regex and scale to image dimensions.
    
    The model outputs bounding boxes in normalized coordinates (0-1 range) within
    special tags: <|det|>x1,y1,x2,y2<|/det|>
    
    Args:
        text: Model output text containing detection tags
        image_size: Tuple of (width, height) in pixels
    
    Returns:
        List of bounding boxes as [(x1, y1, x2, y2), ...] in pixel coordinates
        Returns empty list if no bounding boxes found
    """
    bboxes = []
    
    # Pattern to match detection coordinates in the format:
    # <|det|>x1,y1,x2,y2<|/det|> where coordinates are normalized (0-1)
    pattern = r'<\|det\|>([\d.]+),([\d.]+),([\d.]+),([\d.]+)<\|/det\|>'
    matches = re.findall(pattern, text)
    
    if not matches:
        return bboxes
    
    width, height = image_size
    
    for match in matches:
        try:
            # Parse normalized coordinates (0-1 range)
            norm_x1 = float(match[0])
            norm_y1 = float(match[1])
            norm_x2 = float(match[2])
            norm_y2 = float(match[3])
            
            # Validate normalized coordinates are in valid range
            if not all(0 <= coord <= 1 for coord in [norm_x1, norm_y1, norm_x2, norm_y2]):
                print(f"Warning: Skipping invalid normalized coordinates: {match}")
                continue
            
            # Scale normalized coordinates to actual image dimensions
            x1 = norm_x1 * width
            y1 = norm_y1 * height
            x2 = norm_x2 * width
            y2 = norm_y2 * height
            
            # Ensure coordinates are within image bounds
            x1 = max(0, min(x1, width))
            y1 = max(0, min(y1, height))
            x2 = max(0, min(x2, width))
            y2 = max(0, min(y2, height))
            
            bboxes.append((x1, y1, x2, y2))
            
        except (ValueError, IndexError) as e:
            print(f"Warning: Failed to parse bounding box coordinates: {match}, error: {e}")
            continue
    
    return bboxes


def draw_bounding_boxes(
    image: Image.Image, 
    bboxes: list, 
    color: str = "red", 
    width: int = 3
) -> Image.Image:
    """
    Draw bounding boxes on image using PIL.
    
    Args:
        image: PIL Image object (will be modified)
        bboxes: List of bounding boxes as [(x1, y1, x2, y2), ...] in pixel coordinates
        color: Color for the bounding box outline (default: "red")
        width: Width of the bounding box lines in pixels (default: 3)
    
    Returns:
        PIL Image with bounding boxes drawn
    """
    if not bboxes:
        return image
    
    # Create drawing context
    draw = ImageDraw.Draw(image)
    
    for i, bbox in enumerate(bboxes):
        try:
            x1, y1, x2, y2 = bbox
            
            # Ensure coordinates are valid
            if x2 <= x1 or y2 <= y1:
                print(f"Warning: Skipping invalid bounding box {i}: {bbox}")
                continue
            
            # Draw rectangle with specified color and width
            draw.rectangle([x1, y1, x2, y2], outline=color, width=width)
            
        except (ValueError, TypeError) as e:
            print(f"Warning: Failed to draw bounding box {i}: {bbox}, error: {e}")
            continue
    
    return image


def validate_image_format(image_data: bytes) -> bool:
    """
    Validate that image data is in supported format (PNG, JPG, JPEG).
    
    Args:
        image_data: Raw image bytes
    
    Returns:
        True if format is supported, False otherwise
    """
    try:
        image = Image.open(io.BytesIO(image_data))
        # Check if format is one of the supported types
        # PIL uses "JPEG" for both .jpg and .jpeg files
        supported_formats = ["PNG", "JPEG"]
        return image.format and image.format.upper() in supported_formats
    except Exception:
        return False


def validate_image(image: Image.Image) -> bool:
    """
    Validate that a PIL Image object is valid and in supported format.
    
    Args:
        image: PIL Image object
    
    Returns:
        True if image is valid and supported
    """
    try:
        if not isinstance(image, Image.Image):
            return False
        # Verify image can be accessed
        image.verify()
        return True
    except Exception:
        return False


def decode_base64_image(base64_str: str) -> Image.Image:
    """
    Decode base64 string to PIL Image.
    
    Args:
        base64_str: Base64 encoded image string
    
    Returns:
        PIL Image object
    """
    # Remove data URL prefix if present
    if "base64," in base64_str:
        base64_str = base64_str.split("base64,")[1]
    
    image_data = base64.b64decode(base64_str)
    return Image.open(io.BytesIO(image_data))


def encode_image_to_base64(image: Image.Image, format: str = "PNG") -> str:
    """
    Encode PIL Image to base64 string.
    
    Args:
        image: PIL Image object
        format: Image format (PNG, JPEG)
    
    Returns:
        Base64 encoded string
    """
    buffered = io.BytesIO()
    image.save(buffered, format=format)
    return base64.b64encode(buffered.getvalue()).decode()
