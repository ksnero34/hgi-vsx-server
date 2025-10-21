# syntax=docker/dockerfile:1
FROM node:20-alpine3.19 AS builder

WORKDIR /home/node/cli

# Copy dependency descriptors first to leverage Docker layer caching
COPY --chown=node:node package.json yarn.lock tsconfig.json .yarnrc.yml ./
COPY --chown=node:node .yarn ./.yarn/

# Install dependencies and build the CLI once
RUN corepack enable \
 && corepack prepare yarn@stable --activate \
 && yarn install --immutable

# Copy the remaining sources
COPY --chown=node:node src ./src/
COPY --chown=node:node configs ./configs/
COPY --chown=node:node scripts ./scripts/

# Produce the compiled CLI artifacts
RUN yarn run prepare

FROM node:20-alpine3.19

WORKDIR /home/node/cli

# Copy production dependencies and compiled output from the builder stage
COPY --chown=node:node --from=builder /home/node/cli/node_modules ./node_modules/
COPY --chown=node:node --from=builder /home/node/cli/lib ./lib/
COPY --chown=node:node --from=builder /home/node/cli/package.json ./package.json

ENTRYPOINT ["node", "lib/ovsx"]
