FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "dbt-core>=1.9,<1.10" \
    "dbt-trino>=1.9,<1.10"

WORKDIR /dbt

COPY . .

RUN mkdir -p /root/.dbt
COPY profiles/profiles.yml /root/.dbt/profiles.yml

ENV DBT_PROFILES_DIR=/root/.dbt

RUN dbt deps --project-dir /dbt

ENTRYPOINT ["dbt"]
CMD ["--help"]
