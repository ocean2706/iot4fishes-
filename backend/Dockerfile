backend/Dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir paho-mqtt psycopg2-binary
COPY backend_mqtt_db.py .
CMD ["python", "-u", "backend_mqtt_db.py"]
