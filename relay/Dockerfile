# Relais de sync AImpire : image légère, aucune dépendance, utilisateur non root.
# Contexte de construction : le dossier relay/.
#   docker build -t aimpire-relay relay/

FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=7701 \
    AIMPIRE_RELAY_DATA=/data

WORKDIR /app
COPY package.json server.js ./
RUN mkdir -p /data && chown node:node /data

USER node
EXPOSE 7701
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:7701/health || exit 1

CMD ["node", "server.js"]
