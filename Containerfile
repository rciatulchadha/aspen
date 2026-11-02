FROM registry.access.redhat.com/ubi9/python-311:latest

WORKDIR /opt/app-root/src


# ------------------------------------------------------------
# Python dependencies
# ------------------------------------------------------------

COPY --chown=1001:0 requirements.txt /tmp/requirements.txt

RUN chmod 644 /tmp/requirements.txt && \
    python -m pip install \
        --no-cache-dir \
        --disable-pip-version-check \
        -r /tmp/requirements.txt


# ------------------------------------------------------------
# ASPEN application
# ------------------------------------------------------------

COPY --chown=1001:0 app /opt/app-root/src/app
COPY --chown=1001:0 scripts /opt/app-root/src/scripts


# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

EXPOSE 8085

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8085", "--proxy-headers", "--forwarded-allow-ips=*"]
