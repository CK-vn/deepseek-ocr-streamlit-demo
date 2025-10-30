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
    
    # Create two columns for input and output
    col1, col2 = st.columns([1, 1])
    
    with col1:
        st.subheader("Input")
        
        # Image upload
        uploaded_file = st.file_uploader(
            "Upload an image",
            type=["png", "jpg", "jpeg"],
            help="Supported formats: PNG, JPG, JPEG"
        )
        
        if uploaded_file is not None:
            # Display uploaded image
            image = Image.open(uploaded_file)
            st.image(image, caption="Uploaded Image", use_container_width=True)
            
            # Model size selection
            model_size = st.selectbox(
                "Model Size",
                options=["Tiny", "Small", "Base", "Large", "Gundam"],
                index=4,  # Default to Gundam
                help="Larger models provide better accuracy but take longer to process"
            )
            
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
            
            # Reference text input (only for locate task)
            ref_text = None
            if task_type_value == "locate":
                ref_text = st.text_input(
                    "Reference Text",
                    placeholder="Enter text to locate in the image",
                    help="Specify the text or object you want to find"
                )
            
            # Submit button
            if st.button("Process Image", type="primary", use_container_width=True):
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
                            st.success("Processing complete!")
                            
                        except requests.exceptions.ConnectionError:
                            st.error("❌ Cannot connect to API server. Please check if the service is running.")
                        except requests.exceptions.Timeout:
                            st.error("❌ Request timed out. The image may be too large or complex.")
                        except requests.exceptions.HTTPError as e:
                            st.error(f"❌ API error: {e.response.text}")
                        except Exception as e:
                            st.error(f"❌ An error occurred: {str(e)}")
    
    with col2:
        st.subheader("Output")
        
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
                
                # Display annotated image if available
                if "annotated_image" in result:
                    st.subheader("Annotated Image")
                    try:
                        # Decode base64 image
                        annotated_img_b64 = result["annotated_image"]
                        annotated_img_data = base64.b64decode(annotated_img_b64)
                        annotated_img = Image.open(BytesIO(annotated_img_data))
                        st.image(
                            annotated_img, 
                            caption="Image with Bounding Boxes", 
                            use_container_width=True
                        )
                    except Exception as e:
                        st.warning(f"Could not display annotated image: {str(e)}")
                
                # Display usage statistics
                if "usage" in result:
                    usage = result["usage"]
                    st.caption(f"Tokens used: {usage.get('total_tokens', 'N/A')}")
            else:
                st.warning("No results to display")
        else:
            st.info("👈 Upload an image and click 'Process Image' to see results")
    
    # Footer
    st.divider()
    st.caption("Powered by DeepSeek-OCR | Deployed on AWS EC2")


if __name__ == "__main__":
    main()
