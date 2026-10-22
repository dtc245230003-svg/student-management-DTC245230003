FROM node:20-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY . .
# Hardening: chạy bằng user không phải root
USER node
EXPOSE 3000
CMD ["node", "server.js"]
