# Build stage
FROM node:20-slim AS builder

WORKDIR /app

# Set Puppeteer cache directory
ENV PUPPETEER_CACHE_DIR=/app/.cache/puppeteer

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

# Production stage
FROM node:20-slim

# Install system dependencies and Google Chrome
RUN apt-get update && apt-get install -y wget gnupg ca-certificates --no-install-recommends \
    && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list' \
    && apt-get update \
    && apt-get install -y google-chrome-stable --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Set Puppeteer cache directory and skip download since we'll use the system Chrome
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

COPY package*.json ./
RUN npm install --omit=dev

COPY --from=builder /app/dist ./dist

# Create data directory and ensure permissions
RUN mkdir -p /app/data && chown -R node:node /app/data

# Run as non-privileged user
USER node

ENV DATA_DIR=/app/data

CMD ["npm", "start"]
