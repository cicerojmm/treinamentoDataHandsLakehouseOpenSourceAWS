FROM metabase/metabase:v0.50.26

# Download Starburst Trino driver
USER root
RUN curl -L -o /plugins/starburst.metabase-driver.jar \
    https://github.com/starburstdata/metabase-driver/releases/download/6.1.0/starburst-6.1.0.metabase-driver.jar && \
    chmod 644 /plugins/starburst.metabase-driver.jar

# Run as UID 2000 (metabase default user)
USER 2000
