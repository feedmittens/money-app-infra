# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM node:22-alpine AS builder

WORKDIR /app
COPY client/package*.json ./client/
RUN npm ci --prefix client

COPY client/ ./client/
RUN npm run build --prefix client
# build output is in client/dist/

# ── Stage 2: serve ──────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

COPY --from=builder /app/client/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
