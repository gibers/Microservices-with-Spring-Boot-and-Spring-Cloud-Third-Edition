#!/usr/bin/env bash

function buildCracImageWrapper() {

  local serviceName=$1
  local servicePath=microservices/${serviceName}-service
  local warmupScript=$servicePath/crac/warmup.bash
  local serviceTag=hands-on/${serviceName}-crac

  local servicePort=8080
  local network=chapter07_default
  local springProfiles=docker,kafka,crac

  buildCracImage $serviceName $servicePath $warmupScript $serviceTag $servicePort $network $springProfiles
}

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/commons.bash


log "Cleanup from previously failed builds, if any..."

export COMPOSE_FILE=crac/docker-compose-crac.yml
docker compose down

docker rm -f crac-build

export COMPOSE_FILE=docker-compose-kafka.yml
docker compose down


log "Remove CRaC Images to ensure they all are rebuilt..."

docker rmi hands-on/recommendation-crac hands-on/product-crac hands-on/review-crac hands-on/product-composite-crac || true
echo "Expect no *-crac Docker images before we build them!"
docker images | grep -e "-crac" || true


log "Build form source..."

$SCRIPT_DIR/../gradlew build # -x test # clean
export COMPOSE_FILE=docker-compose-kafka.yml
docker compose build


log "Startup training landscape and populate with test data..."
docker compose up -d
$SCRIPT_DIR/../test-em-all.bash
docker compose rm -fs product-composite


log "Build CRaC images..."
buildCracImageWrapper product-composite
buildCracImageWrapper product
buildCracImageWrapper recommendation
buildCracImageWrapper review

docker images | grep -e "-crac"

log "Bring down the training landscape..."
docker compose down


log "Start up runtime landscape with CRaC images and run tests..."
export COMPOSE_FILE=crac/docker-compose-crac.yml
docker compose up -d

$SCRIPT_DIR/../test-em-all.bash

docker compose logs | grep "CRaC's afterRestore callback method called..."
docker compose logs | grep "Refreshed keys"
docker compose logs | grep "restart completed"
docker compose down
unset COMPOSE_FILE


log "End, all crac-images are built and tested successfully!"
