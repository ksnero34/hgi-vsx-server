# syntax=docker/dockerfile:1
FROM gradle:jdk17 AS builder

# Copy sources
WORKDIR /home/gradle
COPY --chown=gradle:gradle gradlew *.gradle gradle.properties ./
COPY --chown=gradle:gradle gradle ./gradle/
COPY --chown=gradle:gradle scripts ./scripts/
COPY --chown=gradle:gradle src ./src/

ENV CI=true

# Build the server application
RUN --mount=type=secret,id=dv-key,env=DEVELOCITY_ACCESS_KEY \
    ./gradlew --no-daemon assemble

FROM eclipse-temurin:17.0.7_7-jdk

# Install runtime dependencies for health checks
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Create user openvsx and set up home directory
RUN groupadd -r openvsx && useradd --no-log-init -r -g openvsx openvsx
RUN mkdir -p /home/openvsx/server && chown -R openvsx:openvsx /home/openvsx
RUN mkdir -p /var/openvsx/storage && chown -R openvsx:openvsx /var/openvsx
USER openvsx
WORKDIR /home/openvsx/server

# Copy and unpack the server archive
COPY --chown=openvsx:openvsx --from=builder /home/gradle/build/libs/openvsx-server.jar /home/openvsx/
RUN jar -xf /home/openvsx/openvsx-server.jar && rm /home/openvsx/openvsx-server.jar

# Copy runtime scripts and make them executable
COPY --chown=openvsx:openvsx scripts ./scripts/
RUN chmod u+x ./scripts/run-server.sh

# Run the start script
ENTRYPOINT ["./scripts/run-server.sh"]
