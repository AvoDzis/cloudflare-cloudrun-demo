# Stage 1: production dependencies only
FROM node:24-alpine AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Stage 2: runtime image
FROM node:24-alpine

ENV NODE_ENV=production
WORKDIR /app

# Files stay owned by root, so the runtime user can read but not modify them
COPY --from=deps /app/node_modules ./node_modules
COPY package.json server.js ./
COPY src ./src
COPY static ./static

# Non-root user that ships with the official Node image
USER node

EXPOSE 8080

# Used by `docker run`; Cloud Run uses the probes defined in Terraform instead
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/livez', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "server.js"]
