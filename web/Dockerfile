FROM node:22-alpine
WORKDIR /app
COPY server.mjs testupload.mjs package.json ./
COPY public ./public
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server.mjs"]
