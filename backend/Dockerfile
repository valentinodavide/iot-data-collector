# Dockerfile for Node.js backend
FROM node:20-alpine

WORKDIR /app
COPY package.json ./
RUN npm install --silent
COPY . .

EXPOSE 3000
CMD ["npm", "start"]
