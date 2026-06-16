FROM python:3.11-slim-bookworm AS base

ARG FRAPPE_BRANCH=version-15

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget cron \
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

# Copy konsol app from local source (pre-staged by deploy.sh)
COPY --chown=frappe:frappe konsol /tmp/konsol
RUN bench get-app /tmp/konsol

# Bake the freshly-built asset manifest to a path OUTSIDE the sites/ volume.
# At runtime the persistent sites/ volume shadows sites/assets/assets.json with
# a stale copy from a prior image; the configurator restores this baked copy so
# the manifest matches the bundles in this image's app layer. Must run after the
# last asset-producing step (bench init + get-app) and before the VOLUME line.
RUN mkdir -p /home/frappe/baked-assets \
    && cp sites/assets/assets.json /home/frappe/baked-assets/assets.json \
    && (cp sites/assets/assets-rtl.json /home/frappe/baked-assets/assets-rtl.json || true)

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
