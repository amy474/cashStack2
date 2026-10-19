# CashStack API. Node 24 runs the TypeScript directly, so there is no build
# step and what is tested is exactly what ships.
FROM node:24-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

FROM node:24-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY migrations ./migrations
COPY pages ./pages
USER node
EXPOSE 8080
CMD ["node", "src/index.ts"]
