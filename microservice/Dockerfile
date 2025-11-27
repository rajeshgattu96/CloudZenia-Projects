# Dockerfile
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Copy package.json first (good for caching)
COPY package.json ./

# Install dependencies (none extra now, but this keeps it future-proof)
RUN npm install

# Copy app code
COPY app.js ./

# Microservice listens on 8080
EXPOSE 8080

# Default env message (ECS also sets MESSAGE, but this is fallback)
ENV MESSAGE="Hello from Microservice"

# Start the app
CMD ["npm", "start"]
