FROM alpine:3.7
RUN apk add --no-cache tor
COPY genconf.sh /
ENTRYPOINT ["/genconf.sh"]
