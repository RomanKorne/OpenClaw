FROM node:20-bullseye

# Install dependencies for headless browser (Playwright)
RUN apt-get update && apt-get install -y wget ca-certificates --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/agent-browser

# Install playwright and dependencies
COPY package.json package-lock.json* ./
RUN npm ci || true
RUN npx playwright install --with-deps || true

COPY . .

CMD ["node", "index.js"]
