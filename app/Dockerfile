# Small official Python image (Debian based, so it also contains bash -
# needed to "enter the container using bash".
FROM python:3.13-slim

WORKDIR /app

# Do not write .pyc files and print logs immediately (unbuffered).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# The app has no dependencies, so we only copy the code.
COPY app.py .

# Run as a non-root user for security. The app listens on 8080,
# which does not need root.
USER 10001

EXPOSE 8080
CMD ["python", "app.py"]
