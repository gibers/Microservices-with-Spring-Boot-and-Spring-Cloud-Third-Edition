#!/usr/bin/env bash

: ${JAR_FILE=app.jar}
: ${OUT_FOLDER=./checkpoint}
: ${PORT=8080}

function assertCurl() {

  local expectedHttpCode=$1
  local curlCmd="curl \"$2\" -s -w \"%{http_code}\""
  local result=$(eval $curlCmd)
  local httpCode="${result:(-3)}"
  RESPONSE='' && (( ${#result} > 3 )) && RESPONSE="${result%???}"

  if [ "$httpCode" = "$expectedHttpCode" ]; then
    if [ "$httpCode" = "200" ]; then
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

  local expected=$1 actual=$2

  if [ "$actual" = "$expected" ]; then
    echo "Test OK (actual value: $actual)"
  else
    echo "Test FAILED, EXPECTED VALUE: $expected, ACTUAL VALUE: $actual, WILL ABORT"
    exit 1
  fi
}

function testCurlCmd() {
  if $@; then return 0; else return 1; fi
}

function waitForService() {
  url="curl $@ -ks -f -o /dev/null"
  echo -n "Wait for: $url... "
  n=0
  until testCurlCmd $url; do
    n=$((n + 1))
    if [[ $n == 100 ]]; then
      echo "Give up"
      exit 1
    else
      sleep 1
      echo "Retry #$n "
    fi
  done
  echo "DONE, continues..."
}

function runWarmupCalls() {
  assertCurl 200 "localhost:$PORT/recommendation?productId=1"
  assertEqual 3 $(echo $RESPONSE | jq length)
}

function warmup() {
  echo "WaitForService..."
  waitForService localhost:$PORT/actuator
  echo "Wait is over, warmup time!"

  echo "looping test calls"
  for i in {1..100}; do runWarmupCalls; done
}

echo Checkpointing application $JAR_FILE to folder $OUT_FOLDER...

warmup && jcmd $JAR_FILE JDK.checkpoint &

# Will return 137 (SIGKILL) on a successful checkpoint, needs to be wrapped to avoid the image build to fail
java -XX:CRaCCheckpointTo=$OUT_FOLDER -jar $JAR_FILE || if [ $? -eq 137 ]; then exit 0; else exit 1; fi
