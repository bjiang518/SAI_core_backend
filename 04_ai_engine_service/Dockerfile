FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including LaTeX, matplotlib, and Graphviz
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    build-essential \
    pkg-config \
    libfreetype6-dev \
    libpng-dev \
    texlive-latex-base \
    texlive-latex-extra \
    texlive-fonts-recommended \
    ghostscript \
    pdf2svg \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements-railway.txt .
RUN pip install --no-cache-dir -r requirements-railway.txt

# Copy source code
COPY src/ ./src/
COPY start.sh .

# Make start script executable
RUN chmod +x start.sh

# Expose port for Railway
EXPOSE $PORT

# Run the application via startup script
CMD ["./start.sh"]