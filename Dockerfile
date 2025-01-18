# Stage 1: Build dependencies
FROM nvidia/cuda:12.6.3-devel-ubuntu22.04 as builder-base

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Clone and prepare source
FROM builder-base as source
WORKDIR /app
RUN git clone https://github.com/ggerganov/whisper.cpp.git .

# Stage 3: Build the application
FROM source as builder
WORKDIR /app

# Configure CMake with CUDA support
RUN cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="60;70;75;80;86" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath=/usr/local/cuda/lib64" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath=/usr/local/cuda/lib64"

# Build the application
RUN cmake --build build --config Release -j$(nproc)

# Stage 4: Download model
FROM builder as model-downloader
WORKDIR /app
RUN mkdir -p models && \
    wget -P models/ https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin

# Stage 5: Final runtime image
FROM nvidia/cuda:12.6.3-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libstdc++6 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy CUDA libraries and dependencies
COPY --from=builder /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1
COPY --from=builder /usr/local/cuda/lib64/libcudart.so* /usr/local/cuda/lib64/
COPY --from=builder /usr/local/cuda/lib64/libcublas.so* /usr/local/cuda/lib64/
COPY --from=builder /usr/local/cuda/lib64/libcublasLt.so* /usr/local/cuda/lib64/

# Copy application files
COPY --from=builder /app/build/bin/whisper-server ./build/bin/
COPY --from=builder /app/build/lib* ./build/
COPY --from=model-downloader /app/models ./models

# Set library path
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/app/build:$LD_LIBRARY_PATH

# Expose the server port
EXPOSE 7001

# Set environment variables for GPU support
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Start the whisper server with GPU support
CMD ["./build/bin/whisper-server", "-m", "models/ggml-large-v3-turbo-q5_0.bin", "--threads", "6", "--port", "7001", "--language", "auto", "--use-gpu"]