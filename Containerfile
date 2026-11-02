# ============================================================
# ASPEN 0.1.4
#
# Red Hat-only runtime
#
# Builder:
#   Red Hat UBI 10 Python 3.12 Minimal
#
# Runtime:
#   Red Hat UBI 10 Micro
#
# Objective:
#   Move ASPEN from RHEL 9 / Python 3.11 to
#   RHEL 10 / Python 3.12 while retaining the
#   selective-runtime approach validated in 0.1.3.
# ============================================================


# ============================================================
# STAGE 1
# ASPEN PYTHON BUILDER
# ============================================================

FROM registry.access.redhat.com/ubi10/python-312-minimal:latest AS builder

USER 0

WORKDIR /build


# ------------------------------------------------------------
# Install ASPEN Python dependencies.
# ------------------------------------------------------------

COPY requirements.txt /build/requirements.txt

RUN python3.12 -m venv /opt/aspen-venv && \
    /opt/aspen-venv/bin/python -m pip install \
        --no-cache-dir \
        --disable-pip-version-check \
        -r /build/requirements.txt


# ============================================================
# PREPARE MINIMAL RUNTIME FILESYSTEM
# ============================================================

RUN mkdir -p \
        /runtime/usr/bin \
        /runtime/usr/lib64 \
        /runtime/usr/lib \
        /runtime/usr/share \
        /runtime/etc \
        /runtime/etc/pki \
        /runtime/opt


# ============================================================
# PYTHON EXECUTABLE
# ============================================================

RUN cp -a \
        /usr/bin/python3.12 \
        /runtime/usr/bin/


# ============================================================
# PYTHON STANDARD LIBRARY
# ============================================================

RUN cp -a \
        /usr/lib64/python3.12 \
        /runtime/usr/lib64/


# ============================================================
# PYTHON SHARED LIBRARIES
# ============================================================

RUN find /usr/lib64 \
        -maxdepth 1 \
        \( -type f -o -type l \) \
        \( \
            -name 'libpython3.12*.so*' \
            -o -name 'libpython3*.so*' \
        \) \
        -exec cp -a {} /runtime/usr/lib64/ \; \
    || true


# ============================================================
# DISCOVER ACTUAL ELF DEPENDENCIES
# ============================================================

RUN set -eu; \
    \
    : > /tmp/aspen-elf-files; \
    \
    printf '%s\n' \
        /usr/bin/python3.12 \
        >> /tmp/aspen-elf-files; \
    \
    find \
        /usr/lib64/python3.12 \
        /opt/aspen-venv \
        -type f \
        -name '*.so*' \
        >> /tmp/aspen-elf-files; \
    \
    : > /tmp/aspen-libraries; \
    \
    while IFS= read -r binary; do \
        ldd "${binary}" 2>/dev/null \
        | awk '\
            /=> \// {print $3} \
            /^\// {print $1} \
        ' \
        >> /tmp/aspen-libraries \
        || true; \
    done < /tmp/aspen-elf-files; \
    \
    sort -u \
        /tmp/aspen-libraries \
        -o /tmp/aspen-libraries; \
    \
    while IFS= read -r library; do \
        \
        [ -f "${library}" ] || continue; \
        \
        destination="/runtime${library}"; \
        \
        mkdir -p \
            "$(dirname "${destination}")"; \
        \
        cp -L \
            "${library}" \
            "${destination}"; \
        \
    done < /tmp/aspen-libraries


# ============================================================
# DYNAMIC LOADER
# ============================================================

RUN set -eu; \
    \
    for loader in \
        /lib64/ld-linux-x86-64.so.2 \
        /usr/lib64/ld-linux-x86-64.so.2; \
    do \
        \
        if [ -e "${loader}" ]; then \
            \
            mkdir -p \
                "/runtime$(dirname "${loader}")"; \
            \
            cp -L \
                "${loader}" \
                "/runtime${loader}"; \
        fi; \
    done


# ============================================================
# CA CERTIFICATES
# ============================================================

RUN if [ -d /etc/pki ]; then \
        cp -a \
            /etc/pki/. \
            /runtime/etc/pki/; \
    fi


# ============================================================
# TIMEZONE DATA
# ============================================================

RUN if [ -d /usr/share/zoneinfo ]; then \
        cp -a \
            /usr/share/zoneinfo \
            /runtime/usr/share/; \
    fi


# ============================================================
# ASPEN PYTHON ENVIRONMENT
# ============================================================

RUN mkdir -p \
        /runtime/opt/aspen-venv && \
    cp -a \
        /opt/aspen-venv \
        /runtime/opt/aspen-venv/


# ============================================================
# STAGE 2
# FINAL RED HAT UBI 10 MICRO IMAGE
# ============================================================

FROM registry.access.redhat.com/ubi10/ubi-micro:latest

USER 0


# ============================================================
# COPY MINIMAL PYTHON RUNTIME
# ============================================================

COPY --from=builder \
    /runtime/ \
    /


# ============================================================
# ASPEN APPLICATION
# ============================================================

WORKDIR /opt/app-root/src

COPY app \
    /opt/app-root/src/app

COPY scripts \
    /opt/app-root/src/scripts


# ============================================================
# PYTHON ENVIRONMENT
# ============================================================

ENV PATH="/usr/bin:/bin"

ENV PYTHONPATH="/opt/aspen-venv/aspen-venv/lib/python3.12/site-packages:/opt/app-root/src"

ENV PYTHONUNBUFFERED="1"

ENV PYTHONDONTWRITEBYTECODE="1"

ENV PYTHONHASHSEED="random"

ENV HOME="/opt/app-root"


# ============================================================
# OPENSHIFT ARBITRARY UID SUPPORT
# ============================================================

RUN mkdir -p \
        /opt/app-root/src \
        /tmp \
    && chgrp -R 0 \
        /opt/app-root \
        /opt/aspen-venv \
        /tmp \
    && chmod -R g=u \
        /opt/app-root \
        /opt/aspen-venv \
        /tmp \
    && chmod 1777 /tmp


# ============================================================
# NON-ROOT EXECUTION
# ============================================================

USER 1001


# ============================================================
# ASPEN HTTP PORT
# ============================================================

EXPOSE 8085


# ============================================================
# ASPEN STARTUP
# ============================================================

CMD ["/usr/bin/python3.12", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8085", "--proxy-headers", "--forwarded-allow-ips=*"]
