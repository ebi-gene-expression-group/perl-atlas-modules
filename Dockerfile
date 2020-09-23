FROM python:3.8.3-alpine3.11

RUN apk update && apk add bash curl jq
RUN apk add --no-cache g++
RUN pip install pandas

COPY bin/* /usr/local/bin/
COPY lib/* /usr/local/lib/
