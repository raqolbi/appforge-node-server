FROM node:${NODE_VERSION}-alpine
WORKDIR /app
ENV NODE_ENV=${NODE_ENV}
ENV PORT=${INTERNAL_PORT}
COPY package.json ./
COPY package-lock.json* ./
COPY .next ./.next
COPY public* ./public/
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi
EXPOSE ${INTERNAL_PORT}
CMD ["npm", "run", "start"]
