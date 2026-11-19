FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY __init__.py app.py stripe_diagnostic.py /app/podcast_service/
ENV PODCAST_DATA_DIR=/data
EXPOSE 8000
CMD ["uvicorn", "podcast_service.app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
