# 청첩장 server image
# Node 24 이상이어야 합니다. server가 쓰는 node:sqlite 가 20과 22에는 없습니다.
FROM node:24-alpine

WORKDIR /app

# healthcheck에 쓰는 wget 은 alpine의 busybox에 있습니다.

# 청첩장 자산과 server. docker-compose 는 이 경로를 bind mount로 덮어씁니다.
# 그래서 파일을 고치고 재시작만 하면 반영됩니다. mount 없이 image만으로도 동작합니다.
COPY server ./server
COPY src ./src
COPY invitation.conf.example ./invitation.conf.example

# 축하 한마디 DB가 들어갈 곳입니다. compose가 volume을 여기에 붙입니다.
RUN mkdir -p /app/data && chown -R node:node /app

# root로 돌리지 않습니다.
USER node

ENV NODE_ENV=production \
    PORT=8080 \
    CONF_FILE=/app/invitation.conf \
    SRC_DIR=/app/src \
    DB_FILE=/app/data/guestbook.db

EXPOSE 8080

CMD ["node", "server/server.mjs"]
