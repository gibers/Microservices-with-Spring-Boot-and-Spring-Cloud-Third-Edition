#!/usr/bin/env bash

function buildCracImage() {

  local serviceName=$1
  local servicePath=$2
  local warmupScript=$3
  local serviceTag=$4
  local servicePort=$5
  local network=$6
  local springProfiles=$7

  local baseImageTag=crac-base

  log "Building CRaC image $serviceTag in $servicePath..."

  echo "Building base image $baseImageTag in $servicePath..."
  docker build -f crac/Dockerfile-crac-base -t $baseImageTag $servicePath

  echo "Warmup $serviceName..."
  if [ -f checkpoint ]; then
    rm -r checkpoint
  fi
  docker rm -f crac-build

  docker run -d --name crac-build -p 8080:$servicePort --network $network \
      --cap-add=CHECKPOINT_RESTORE --cap-add=SYS_PTRACE \
      -e SPRING_PROFILES_ACTIVE="$springProfiles" \
      -v $PWD/checkpoint:/checkpoint $baseImageTag \
      java -XX:CRaCCheckpointTo=checkpoint -jar app.jar

  echo "Running warmup script $warmupScript..."
  $warmupScript

  echo "Checkpoint $serviceName..."
  docker exec crac-build jcmd app.jar JDK.checkpoint

  until waitForContainerToStop crac-build; do
      echo "Waiting for the checkpoint to be ready..."
      sleep 1
  done
  docker rm -f crac-build

  echo "Building CRaC image $serviceTag..."
  docker build -f crac/Dockerfile-crac -t $serviceTag .
}

LOG_NO=0
function log() {

  LOG_NO=$(expr $LOG_NO + 1)
  local MSG="#$LOG_NO: $(date +%H:%M:%S) - $1"
  local LEN=$(expr ${#MSG} + 2)
  local HEADER=$(printf -- '-%.0s' $(seq 1 $LEN))

  echo -e "\n+${HEADER}+"
  echo "| $MSG |"
  echo "+${HEADER}+"
}

function assertCurl() {

  local expectedHttpCode=$1
  local curlCmd="$2 -w \"%{http_code}\""
  local result=$(eval $curlCmd)
  local httpCode="${result:(-3)}"
  RESPONSE='' && (( ${#result} > 3 )) && RESPONSE="${result%???}"

  if [ "$httpCode" = "$expectedHttpCode" ]
  then
    if [ "$httpCode" = "200" ]
    then
      echo "Test OK (HTTP Code: $httpCode)"
    else
      echo "Test OK (HTTP Code: $httpCode, $RESPONSE)"
    fi
  else
    echo  "Test FAILED, EXPECTED HTTP Code: $expectedHttpCode, GOT: $httpCode, WILL ABORT!"
    echo  "- Failing command: $curlCmd"
    echo  "- Response Body: $RESPONSE"
    exit 1
  fi
}

function assertEqual() {

  local expected=$1
  local actual=$2

  if [ "$actual" = "$expected" ]
  then
    echo "Test OK (actual value: $actual)"
  else
    echo "Test FAILED, EXPECTED VALUE: $expected, ACTUAL VALUE: $actual, WILL ABORT"
    exit 1
  fi
}

function testUrl() {
  url=$@
  if $url -ks -f -o /dev/null
  then
    return 0
  else
    return 1
  fi;
}

function waitForService() {
  url=$@
  echo -n "Wait for: $url... "
  n=0
  until testUrl $url
  do
    n=$((n + 1))
    if [[ $n == 120 ]]
    then
      echo " Give up"
      exit 1
    else
      sleep 1
      echo -n ", retry #$n "
    fi
  done
  echo "DONE, continues..."
}

function waitForContainerToStop() {
    local containerName=$1
    count=$(docker ps -f name=$containerName -q | wc -l | xargs)
    if [ "$count" = "0" ] ; then
        echo "Container down"
    else
        echo "Container still running..."
    fi
    return $count
}
