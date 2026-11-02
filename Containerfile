# ============================================================
# ASPEN BUILDER
# ============================================================

FROM registry.access.redhat.com/ubi9/python-311:latest AS builder

WORKDIR /opt/app-root/src

COPY --chown=1001:0 requirements.txt .

RUN mkdir -p /opt/app-root/python && \
    python -m pip install \
        --no-cache-dir \
        --disable-pip-version-check \
        --target /opt/app-root/python \
        -r requirements.txt


# ============================================================
# ASPEN RUNTIME
# ============================================================

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

USER 0

RUN microdnf install -y \
        python3.11 \
    && microdnf clean all \
    && rm -rf /var/cache/dnf


# ============================================================
# APPLICATION
# ============================================================

WORKDIR /opt/app-root/src

COPY --from=builder \
    /opt/app-root/python \
    /opt/app-root/python

COPY app ./app
COPY scripts ./scripts


# ============================================================
# PYTHON
# ============================================================

ENV PYTHONPATH=/opt/app-root/python
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1


# ============================================================
# OPENSHIFT PERMISSIONS
# ============================================================

RUN mkdir -p /opt/app-root/src && \
    chgrp -R 0 /opt/app-root && \
    chmod -R g=u /opt/app-root


# OpenShift compatible non-root user
USER 1001


# ============================================================
# ASPEN
# ============================================================

EXPOSE 8085

CMD ["python3.11", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8085", "--proxy-headers", "--forwarded-allow-ips=*"]
