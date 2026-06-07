FROM python:3.11-slim

WORKDIR /airbyte/integration_code

COPY pyproject.toml README.md ./
COPY source_d365_fno/ ./source_d365_fno/

RUN pip install --no-cache-dir .

ENV AIRBYTE_ENTRYPOINT="python -m source_d365_fno.run"
ENTRYPOINT ["python", "-m", "source_d365_fno.run"]

LABEL io.airbyte.name=source-d365-fno
LABEL io.airbyte.version=0.1.0
