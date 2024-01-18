#!/bin/bash

# v1.0.0:

VERSION="1.0.0"
script_pwd=$(cd "$(dirname "$0")";pwd)
echo ${script_pwd}

GOOS="linux"
GOARCH="amd64"
DEV_TYPE="amd64"
BACKEND_ADDR="https://internal.api.paigod.work"
TEST_BACKEND_ADDR="http://api.test.paigod.work"
DATA_CHANNEL_ADDR="https://datachannel.painet.work"
TEST_DATA_CHANNEL_ADDR="http://datachannel.test.painet.work"
BROKER_ADDR="47.114.74.103:1883"

echo "build info: GOOS=${GOOS} GOARCH=${GOARCH} DEV_TYPE=${DEV_TYPE} VERSION=${VERSION}"
echo "Production env addr: BACKEND_ADDR=${BACKEND_ADDR} DATA_CHANNEL_ADDR=${DATA_CHANNEL_ADDR}"
echo "Test env addr: TEST_BACKEND_ADDR=${TEST_BACKEND_ADDR} TEST_DATA_CHANNEL_ADDR=${TEST_DATA_CHANNEL_ADDR}"

GOOS=${GOOS} GOARCH=${GOARCH} CGO_ENABLED=0 go build \
  -o collect-"${DEV_TYPE}-${VERSION}-${GOOS}-${GOARCH}" \
  -ldflags "-s -w -X 'github.com/PPIO/pi-collect/build.DevType=${DEV_TYPE}' \
  -X 'github.com/PPIO/pi-collect/build.DataChannelAddr=${DATA_CHANNEL_ADDR}' \
  -X 'github.com/PPIO/pi-collect/build.BackendAddr=${BACKEND_ADDR}' \
  -X 'github.com/PPIO/pi-collect/build.Version=${VERSION}' \
  -X 'github.com/PPIO/pi-collect/build.TestBackendAddr=${TEST_BACKEND_ADDR}' \
  -X 'github.com/PPIO/pi-collect/build.TestDataChannelAddr=${TEST_DATA_CHANNEL_ADDR}'" \
  $(dirname $0)/../main.go

cp ./collect-"${DEV_TYPE}-${VERSION}-${GOOS}-${GOARCH}" ./collect
