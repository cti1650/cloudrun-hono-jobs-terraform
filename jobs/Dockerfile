FROM node:24-slim AS builder

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --no-update-notifier

COPY tsconfig.json ./
COPY src/ src/
RUN npm run build

FROM node:24-slim

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --no-update-notifier --omit=dev

COPY --from=builder /app/dist/ dist/

CMD ["node", "dist/index.js"]
