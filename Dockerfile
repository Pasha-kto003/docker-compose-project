FROM node:20-alpine3.20 AS builder

WORKDIR /app

# Копируем файлы зависимостей
COPY package.json package-lock.json ./

# Устанавливаем зависимости
RUN npm ci --omit=dev

FROM node:20-alpine3.20 AS runner

WORKDIR /app

ENV NODE_ENV=production

# Копируем установленные зависимости из этапа builder
COPY --from=builder /app/node_modules ./node_modules

# Копируем исходный код
COPY index.js ./
COPY package.json ./

# Копируем статику
COPY public ./public

# Создаём не-root пользователя
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

USER nodejs

EXPOSE 3000

CMD ["node", "index.js"]
