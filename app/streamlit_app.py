"""
Streamlit Frontend for DeepSeek-OCR

Interactive web interface for OCR tasks.
"""

import streamlit as st
import requests
from PIL import Image
import base64
from io import BytesIO
from typing import Optional


# Page configuration
st.set_page_config(
    page_title="DeepSeek-OCR",
    page_icon="🔍",
    layout="wide"
)

# API endpoint
API_URL = "http://localhost:8000"


def encode_image_to_base64(image: Image.Image) -> str:
    """Convert PIL Image to base64 string."""
    buffered = BytesIO()
    image.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode()


def call_api(
    image: Image.Image,
    model_size: str,
    task_type: str,
    ref_text: Optional[str] = None
) -> dict:
    """
    Call the FastAPI server to process the image.
    
    Args:
        image: PIL Image object
        model_size: Model size configuration
        task_type: Type of OCR task
        ref_text: Reference text for locate task
    
    Returns:
        API response as dictionary
    """
    # Convert image to base64
    img_b64 = encode_image_to_base64(image)
    
    # Build request payload
    payload = {
        "model": "deepseek-ocr",
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": f"{task_type.replace('_', ' ').title()}."},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{img_b64}"
                        }
                    }
                ]
            }
        ],
        "temperature": 0.0,
        "max_tokens": 4096,
        "extra_body": {
            "model_size": model_size,
            "task_type": task_type,
            "ref_text": ref_text
        }
    }
    
    # Send request
    response = requests.post(
        f"{API_URL}/v1/chat/completions",
        json=payload,
        timeout=120
    )
    
    response.raise_for_status()
    return response.json()


def main():
    """Main Streamlit application."""
    
    # Title and description
    st.title("🔍 DeepSeek-OCR")
    st.markdown("""
    Extract text and structured data from images using DeepSeek-OCR.
    
    **Supported tasks:**
    - **Free OCR**: Extract all text from the image
    - **Convert to Markdown**: Convert document to markdown format
    - **Parse Figure**: Extract structured data from charts and figures
    - **Locate Object**: Find specific text or objects in the image
    """)
    
    st.divider()
    
    # Image upload
    uploaded_file = st.file_uploader(
        "Upload an image",
        type=["png", "jpg", "jpeg"],
        help="Supported formats: PNG, JPG, JPEG"
    )
    
    if uploaded_file is not None:
        # Store uploaded image in session state
        image = Image.open(uploaded_file)
        st.session_state["uploaded_image"] = image
        
        # Configuration section
        st.subheader("⚙️ Configuration")
        
        col_config1, col_config2, col_config3 = st.columns([1, 1, 1])
        
        with col_config1:
            # Model size selection
            model_size = st.selectbox(
                "Model Size",
                options=["Tiny", "Small", "Base", "Large", "Gundam"],
                index=4,  # Default to Gundam
                help="Larger models provide better accuracy but take longer to process"
            )
        
        with col_config2:
            # Task type selection
            task_type = st.selectbox(
                "Task Type",
                options=[
                    ("Free OCR", "free_ocr"),
                    ("Convert to Markdown", "markdown"),
                    ("Parse Figure", "parse_figure"),
                    ("Locate Object", "locate")
                ],
                format_func=lambda x: x[0],
                help="Select the type of OCR task to perform"
            )
        
        task_type_value = task_type[1]
        
        with col_config3:
            # Reference text input (only for locate task)
            ref_text = None
            if task_type_value == "locate":
                ref_text = st.text_input(
                    "Reference Text",
                    placeholder="Enter text to locate",
                    help="Specify the text or object you want to find"
                )
            else:
                st.write("")  # Empty space for alignment
        
        # Submit button
        if st.button("🚀 Process Image", type="primary", use_container_width=True):
            if task_type_value == "locate" and not ref_text:
                st.error("Please enter reference text for the Locate task")
            else:
                with st.spinner("Processing image..."):
                    try:
                        # Call API
                        result = call_api(
                            image=image,
                            model_size=model_size,
                            task_type=task_type_value,
                            ref_text=ref_text
                        )
                        
                        # Store result in session state
                        st.session_state["result"] = result
                        st.session_state["processed_image"] = image
                        st.success("✅ Processing complete!")
                        
                    except requests.exceptions.ConnectionError:
                        st.error("❌ Cannot connect to API server. Please check if the service is running.")
                    except requests.exceptions.Timeout:
                        st.error("❌ Request timed out. The image may be too large or complex.")
                    except requests.exceptions.HTTPError as e:
                        st.error(f"❌ API error: {e.response.text}")
                    except Exception as e:
                        st.error(f"❌ An error occurred: {str(e)}")
        
        st.divider()
    
    # Create two columns for input and output
    col1, col2 = st.columns([1, 1])
    
    with col1:
        st.subheader("📥 Input")
        
        if "uploaded_image" in st.session_state:
            st.image(st.session_state["uploaded_image"], caption="Uploaded Image", use_container_width=True)
        else:
            st.info("👆 Upload an image to get started")
    
    with col2:
        st.subheader("📤 Output")
        
        # Display results if available
        if "result" in st.session_state:
            result = st.session_state["result"]
            
            # Extract text from response
            if "choices" in result and len(result["choices"]) > 0:
                output_text = result["choices"][0]["message"]["content"]
                
                # Display text output
                st.text_area(
                    "Extracted Text",
                    value=output_text,
                    height=300,
                    help="Copy the extracted text from here"
                )
                
                # Copy button
                if st.button("📋 Copy to Clipboard"):
                    st.code(output_text, language=None)
                    st.info("Text displayed above - use your browser's copy function")
                
                # Display usage statistics
                if "usage" in result:
                    usage = result["usage"]
                    st.caption(f"Tokens used: {usage.get('total_tokens', 'N/A')}")
                
                # Extract and display bounding boxes
                import re
                bbox_pattern = r'<\|det\|>\[\[([^\]]+)\]\]<\|/det\|>'
                bbox_matches = re.findall(bbox_pattern, output_text)
                
                if bbox_matches and "processed_image" in st.session_state:
                    st.divider()
                    st.markdown("### Extracted Bounding Boxes")
                    
                    # Parse bounding boxes
                    bboxes = []
                    for match in bbox_matches:
                        try:
                            coords = [int(x.strip()) for x in match.split(',')]
                            if len(coords) == 4:
                                bboxes.append(coords)
                        except:
                            continue
                    
                    if bboxes:
                        # Draw bounding boxes on image
                        from PIL import ImageDraw
                        annotated_img = st.session_state["processed_image"].copy()
                        draw = ImageDraw.Draw(annotated_img)
                        
                        for bbox in bboxes:
                            x1, y1, x2, y2 = bbox
                            draw.rectangle([x1, y1, x2, y2], outline="red", width=3)
                        
                        st.image(
                            annotated_img,
                            caption=f"Image with {len(bboxes)} detected bounding box(es)",
                            use_container_width=True
                        )
                        
                        # Display bounding box coordinates
                        with st.expander("View Bounding Box Coordinates"):
                            for i, bbox in enumerate(bboxes, 1):
                                st.text(f"Box {i}: [{bbox[0]}, {bbox[1]}, {bbox[2]}, {bbox[3]}]")
                    else:
                        st.info("No valid bounding boxes found in the output")
            else:
                st.warning("No results to display")
        else:
            st.info("👈 Upload an image and click 'Process Image' to see results")
    
    # Footer
    st.divider()
    st.caption("Powered by DeepSeek-OCR | Deployed on AWS EC2")


if __name__ == "__main__":
    main()
