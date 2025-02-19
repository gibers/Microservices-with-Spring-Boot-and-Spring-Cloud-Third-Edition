#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/../../../crac/commons.bash

waitForService curl http://localhost:8080/actuator/health

for i in {1..3}; do
  assertCurl 200 "curl -s localhost:8080/product/1"
  assertEqual 1 $(echo $RESPONSE | jq ".productId")
done
