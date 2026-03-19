FROM python:3.12-slim

WORKDIR /app

# System dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
    && rm -rf /var/lib/apt/lists/*

# Clone repository
RUN git clone https://github.com/zai-org/GLM-OCR.git .

# Install CPU-only torch first, then package with all extras
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir ".[selfhosted,server]"

# Self-hosted CPU mode defaults
ENV GLMOCR_MODE=selfhosted
ENV GLMOCR_LAYOUT_DEVICE=cpu
ENV GLMOCR_ENABLE_LAYOUT=true
ENV GLMOCR_OCR_API_HOST=ollama
ENV GLMOCR_OCR_API_PORT=11434

EXPOSE 8511

ENTRYPOINT ["python", "-m", "glmocr.server"]
