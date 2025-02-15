# ---- Base Node ----
FROM --platform=linux/amd64 node:19-alpine AS base
WORKDIR /app
COPY package*.json ./

# ---- Dependencies ----
FROM --platform=linux/amd64 base AS dependencies
RUN npm ci

# ---- Build ----
FROM --platform=linux/amd64 dependencies AS build
COPY . .
RUN npm run build

# ---- Production ----
FROM --platform=linux/amd64 node:19-alpine AS production
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/package*.json ./
COPY --from=build /app/next.config.js ./next.config.js
COPY --from=build /app/next-i18next.config.js ./next-i18next.config.js

# Expose the port the app will run on
EXPOSE 3000 8080

# Start the application
CMD ["npm", "start"]
