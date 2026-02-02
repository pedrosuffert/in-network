# Add the --platform flag here
FROM --platform=linux/amd64 p4lang/behavioral-model:latest

USER root

RUN apt-get update && apt-get install -y iproute2 tcpdump && \
    mkdir -p /config && \
    chmod 777 /config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /config

ENV JSON_FILE="router.json"
ENV THRIFT_PORT=9090

ENTRYPOINT ["sh", "-c", "simple_switch --log-console --log-level info --thrift-port ${THRIFT_PORT} -i 0@eth0 /config/${JSON_FILE}"]
