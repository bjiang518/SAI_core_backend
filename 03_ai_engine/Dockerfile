FROM python:3.11-slim

WORKDIR /app

# Copy requirements first for better caching
COPY requirements-railway.txt .
RUN pip install --no-cache-dir -r requirements-railway.txt

# Copy source code
COPY src/ ./src/
COPY .env.example .env
COPY start.sh .

# Run the application via startup script
CMD ["./start.sh"]