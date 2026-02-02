FROM alpine:latest

USER root

RUN apk add --no-cache iproute2 iputils tcpdump bash

ENTRYPOINT ["/bin/sh", "-c", "exec sleep infinity"]