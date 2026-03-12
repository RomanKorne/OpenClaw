FROM node:20-bullseye
WORKDIR /usr/src/proactive-agent
COPY package.json package-lock.json* ./
RUN npm ci || true
COPY . .
CMD ["node","proactive_test.js"]
