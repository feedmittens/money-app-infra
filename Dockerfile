# Build stage for the frontend
FROM node:22-alpine AS frontend-builder

WORKDIR /app

# Copy package files
COPY client/package*.json ./client/
RUN cd client && npm ci --silent

# Copy client source
COPY client ./client

# Build frontend
RUN cd client && npm run build

# Final stage - API server and Nginx
FROM node:22-alpine

# Install dependencies: Nginx, PostgreSQL client, OpenSSL
RUN apk add --no-cache nginx postgresql-client openssl curl bash

WORKDIR /opt/money-app

# Copy package files for server
COPY server/package*.json ./server/
RUN cd server && npm ci --silent

# Copy server source and schema
COPY server ./server

# Copy built frontend from builder stage
COPY --from=frontend-builder /app/client/dist ./client/dist

# Create directories
RUN mkdir -p /var/www/html /etc/nginx/ssl

# Copy frontend to Nginx root
RUN cp -r client/dist/* /var/www/html/

# Create Nginx configuration
COPY docker/nginx.conf /etc/nginx/sites-available/money-app
RUN ln -sf /etc/nginx/sites-available/money-app /etc/nginx/sites-enabled/money-app && \
    rm -f /etc/nginx/sites-enabled/default && \
    nginx -t

# Copy entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports: 80 (HTTP), 443 (HTTPS), 3001 (API)
EXPOSE 80 443 3001

ENTRYPOINT ["/entrypoint.sh"]
