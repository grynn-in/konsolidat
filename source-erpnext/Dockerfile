FROM python:3.11-slim

WORKDIR /airbyte/integration_code

COPY pyproject.toml README.md ./
COPY source_erpnext/ ./source_erpnext/

RUN pip install --no-cache-dir .

ENV AIRBYTE_ENTRYPOINT="python -m source_erpnext.run"
ENTRYPOINT ["python", "-m", "source_erpnext.run"]

LABEL io.airbyte.name=source-erpnext
LABEL io.airbyte.version=0.1.0
