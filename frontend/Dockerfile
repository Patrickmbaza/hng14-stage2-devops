FROM node:20-alpine AS builder

WORKDIR /app

COPY frontend/package*.json ./

RUN npm ci

COPY frontend ./

RUN npm prune --omit=dev

FROM node:20-alpine

ENV NODE_ENV=production

RUN apk upgrade --no-cache \
    && addgroup -S appgroup \
    && adduser -S appuser -G appgroup \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx \
    && rm -rf /usr/local/lib/node_modules/npm

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /app /app

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=6 CMD node -e "const http=require('http');const port=process.env.FRONTEND_PORT||3000;const req=http.get({host:'127.0.0.1',port,path:'/health',timeout:3000},res=>process.exit(res.statusCode===200?0:1));req.on('error',()=>process.exit(1));req.on('timeout',()=>{req.destroy();process.exit(1);});"

CMD ["node", "app.js"]
