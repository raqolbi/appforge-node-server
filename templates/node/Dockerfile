FROM node:${NODE_VERSION}-alpine
WORKDIR /app
ENV NODE_ENV=${NODE_ENV}
ENV PORT=${INTERNAL_PORT}
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev
COPY . .
EXPOSE ${INTERNAL_PORT}
CMD ["npm", "start"]
