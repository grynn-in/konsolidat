FROM python:3.11-slim-bookworm AS base

ARG FRAPPE_BRANCH=version-15
ARG KONSOL_REPO=https://github.com/grynn-in/konsol.git
ARG KONSOL_BRANCH=main

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget \
    mariadb-client \
    xfonts-75dpi xfonts-base \
    libfontconfig1 libxrender1 libxext6 \
    build-essential python3-dev \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && curl -sL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb -o /tmp/wkhtmltox.deb \
    && dpkg -i /tmp/wkhtmltox.deb || apt-get install -fy \
    && rm /tmp/wkhtmltox.deb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create frappe user
RUN useradd -m -s /bin/bash frappe
USER frappe
WORKDIR /home/frappe

# Install bench
RUN pip install --user frappe-bench \
    && echo 'export PATH=$PATH:/home/frappe/.local/bin' >> /home/frappe/.bashrc
ENV PATH="/home/frappe/.local/bin:${PATH}"

# Init bench (skip redis config — we pass via environment)
RUN bench init \
    --skip-redis-config-generation \
    --frappe-branch ${FRAPPE_BRANCH} \
    frappe-bench

WORKDIR /home/frappe/frappe-bench

# Install konsol app
RUN bench get-app konsol ${KONSOL_REPO} --branch ${KONSOL_BRANCH}

# Install dbt + clickhouse adapter in bench venv (for pipeline runner)
RUN ./env/bin/pip install dbt-core dbt-clickhouse

# Copy entrypoint
COPY --chown=frappe:frappe entrypoint.sh /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint.sh

# Volumes for persistent data
VOLUME ["/home/frappe/frappe-bench/sites"]

EXPOSE 8069

ENTRYPOINT ["/home/frappe/entrypoint.sh"]
CMD ["web"]
