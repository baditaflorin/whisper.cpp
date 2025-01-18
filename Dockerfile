FROM debian:bullseye-slim

# Install required build dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Clone whisper.cpp repository
RUN git clone https://github.com/ggerganov/whisper.cpp.git .

# Build the project
RUN make

# Create models directory and download the model
RUN mkdir -p models && \
    wget -P models/ https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin

# Expose the server port
EXPOSE 7001

# Start the whisper server
CMD ["./build/bin/whisper-server", "-m", "models/ggml-large-v3-turbo-q5_0.bin", "--threads", "6", "--port", "7001", "--language", "auto"]