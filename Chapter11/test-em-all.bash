#!/usr/bin/env bash
#
# Sample usage:
#
#   HOST=localhost PORT=7000 ./test-em-all.bash
#
: ${HOST=localhost}
: ${PORT=8443}
: ${PROD_ID_REVS_RECS=1}
: ${PROD_ID_NOT_FOUND=13}
: ${PROD_ID_NO_RECS=113}
: ${PROD_ID_NO_REVS=213}

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
    if [[ $n == 100 ]]
    then
      echo " Give up"
      exit 1
    else
      sleep 3
      echo -n ", retry #$n "
    fi
  done
  echo "DONE, continues..."
}

function testCompositeCreated() {

    # Expect that the Product Composite for productId $PROD_ID_REVS_RECS has been created with three recommendations and three reviews
    if ! assertCurl 200 "curl $AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"
    then
        echo -n "FAIL"
        return 1
    fi

    set +e
    assertEqual "$PROD_ID_REVS_RECS" $(echo $RESPONSE | jq .productId)
    if [ "$?" -eq "1" ] ; then return 1; fi

    assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
    if [ "$?" -eq "1" ] ; then return 1; fi

    assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")
    if [ "$?" -eq "1" ] ; then return 1; fi

    set -e
}

function waitForMessageProcessing() {
    echo "Wait for messages to be processed... "

    # Give background processing some time to complete...
    sleep 1

    n=0
    until testCompositeCreated
    do
        n=$((n + 1))
        if [[ $n == 40 ]]
        then
            echo " Give up"
            exit 1
        else
            sleep 6
            echo -n ", retry #$n "
        fi
    done
    echo "All messages are now processed!"
}

function recreateComposite() {
  local productId=$1
  local composite=$2

  assertCurl 202 "curl -X DELETE $AUTH -k https://$HOST:$PORT/product-composite/${productId} -s"
  assertEqual 202 $(curl -X POST -s -k https://$HOST:$PORT/product-composite -H "Content-Type: application/json" -H "Authorization: Bearer $ACCESS_TOKEN" --data "$composite" -w "%{http_code}")
}

function setupTestdata() {

  body="{\"productId\":$PROD_ID_NO_RECS"
  body+=\
',"name":"product name A","weight":100, "reviews":[
  {"reviewId":1,"author":"author 1","subject":"subject 1","content":"content 1"},
  {"reviewId":2,"author":"author 2","subject":"subject 2","content":"content 2"},
  {"reviewId":3,"author":"author 3","subject":"subject 3","content":"content 3"}
]}'
  recreateComposite "$PROD_ID_NO_RECS" "$body"

  body="{\"productId\":$PROD_ID_NO_REVS"
  body+=\
',"name":"product name B","weight":200, "recommendations":[
  {"recommendationId":1,"author":"author 1","rate":1,"content":"content 1"},
  {"recommendationId":2,"author":"author 2","rate":2,"content":"content 2"},
  {"recommendationId":3,"author":"author 3","rate":3,"content":"content 3"}
]}'
  recreateComposite "$PROD_ID_NO_REVS" "$body"


  body="{\"productId\":$PROD_ID_REVS_RECS"
  body+=\
',"name":"product name C","weight":300, "recommendations":[
      {"recommendationId":1,"author":"author 1","rate":1,"content":"content 1"},
      {"recommendationId":2,"author":"author 2","rate":2,"content":"content 2"},
      {"recommendationId":3,"author":"author 3","rate":3,"content":"content 3"}
  ], "reviews":[
      {"reviewId":1,"author":"author 1","subject":"subject 1","content":"content 1"},
      {"reviewId":2,"author":"author 2","subject":"subject 2","content":"content 2"},
      {"reviewId":3,"author":"author 3","subject":"subject 3","content":"content 3"}
  ]}'
  recreateComposite "$PROD_ID_REVS_RECS" "$body"

}

set -e

echo "Start Tests:" `date`

echo "HOST=${HOST}"
echo "PORT=${PORT}"

if [[ $@ == *"start"* ]]
then
  echo "Restarting the test environment..."
  echo "$ docker compose down --remove-orphans"
  docker compose down --remove-orphans
  echo "$ docker compose up -d"
  docker compose up -d
fi

waitForService curl -k https://$HOST:$PORT/actuator/health

ACCESS_TOKEN=$(curl -k https://writer:secret-writer@$HOST:$PORT/oauth2/token -d grant_type=client_credentials -d scope="product:read product:write" -s | jq .access_token -r)
echo ACCESS_TOKEN=$ACCESS_TOKEN
AUTH="-H \"Authorization: Bearer $ACCESS_TOKEN\""

# Verify access to Eureka and that all four microservices are registered in Eureka
assertCurl 200 "curl -H "accept:application/json" -k https://u:p@$HOST:$PORT/eureka/api/apps -s"
assertEqual 6 $(echo $RESPONSE | jq ".applications.application | length")

setupTestdata

waitForMessageProcessing

# Verify that a normal request works, expect three recommendations and three reviews
assertCurl 200 "curl $AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"
assertEqual $PROD_ID_REVS_RECS $(echo $RESPONSE | jq .productId)
assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

# Verify that a 404 (Not Found) error is returned for a non-existing productId ($PROD_ID_NOT_FOUND)
assertCurl 404 "curl $AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_NOT_FOUND -s"
assertEqual "No product found for productId: $PROD_ID_NOT_FOUND" "$(echo $RESPONSE | jq -r .message)"

# Verify that no recommendations are returned for productId $PROD_ID_NO_RECS
assertCurl 200 "curl $AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_NO_RECS -s"
assertEqual $PROD_ID_NO_RECS $(echo $RESPONSE | jq .productId)
assertEqual 0 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

# Verify that no reviews are returned for productId $PROD_ID_NO_REVS
assertCurl 200 "curl $AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_NO_REVS -s"
assertEqual $PROD_ID_NO_REVS $(echo $RESPONSE | jq .productId)
assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 0 $(echo $RESPONSE | jq ".reviews | length")

# Verify that a 422 (Unprocessable Entity) error is returned for a productId that is out of range (-1)
assertCurl 422 "curl $AUTH -k https://$HOST:$PORT/product-composite/-1 -s"
assertEqual "\"Invalid productId: -1\"" "$(echo $RESPONSE | jq .message)"

# Verify that a 400 (Bad Request) error error is returned for a productId that is not a number, i.e. invalid format
assertCurl 400 "curl $AUTH -k https://$HOST:$PORT/product-composite/invalidProductId -s"
assertEqual "\"Type mismatch.\"" "$(echo $RESPONSE | jq .message)"

# Verify that a request without access token fails on 401, Unauthorized
assertCurl 401 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"

# Verify that the reader - client with only read scope can call the read API but not delete API.
READER_ACCESS_TOKEN=$(curl -k https://reader:secret-reader@$HOST:$PORT/oauth2/token -d grant_type=client_credentials -d scope="product:read" -s | jq .access_token -r)
echo READER_ACCESS_TOKEN=$READER_ACCESS_TOKEN
READER_AUTH="-H \"Authorization: Bearer $READER_ACCESS_TOKEN\""

assertCurl 200 "curl $READER_AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"
assertCurl 403 "curl -X DELETE $READER_AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"

# Verify access to Swagger and OpenAPI URLs
echo "Swagger/OpenAPI tests"
assertCurl 302 "curl -ks  https://$HOST:$PORT/openapi/swagger-ui.html"
assertCurl 200 "curl -ksL https://$HOST:$PORT/openapi/swagger-ui.html"
assertCurl 200 "curl -ks  https://$HOST:$PORT/openapi/webjars/swagger-ui/index.html?configUrl=/v3/api-docs/swagger-config"
assertCurl 200 "curl -ks  https://$HOST:$PORT/openapi/v3/api-docs"
assertEqual "3.0.1" "$(echo $RESPONSE | jq -r .openapi)"
assertEqual "https://$HOST:$PORT" "$(echo $RESPONSE | jq -r '.servers[0].url')"
assertCurl 200 "curl -ks  https://$HOST:$PORT/openapi/v3/api-docs.yaml"

if [[ $@ == *"stop"* ]]
then
    echo "We are done, stopping the test environment..."
    echo "$ docker compose down"
    docker compose down
fi

echo "End, all tests OK:" `date`


# 8443 => gateway
# 8761 => eureka

curl -H "accept:application/json" https://u:p@localhost:8443/eureka/api/apps -ks | jq -r .applications.application[].instance[].instanceId

# client credentials grant flow
curl -k https://writer:secret-writer@localhost:8443/oauth2/token -d grant_type=client_credentials -d scope="product:read product:write" -s | jq .
curl -k https://reader:secret-reader@localhost:8443/oauth2/token -d grant_type=client_credentials -d scope="product:read" -s | jq .

# code grant flow for reader
https://localhost:8443/oauth2/authorize?response_type=code&client_id=reader&redirect_uri=https://my.redirect.uri&scope=product:read&state=35725
https://my.redirect.uri/?
code=ovf-s3KIR9_jw0jKbqZopJ118stufIC3S1xXWtrAzX6k0IJZUE_K_a-lAtUfGdRbnLHT0i1ViDCSfsLDOglAyAwWMzMYPM1vuiFgSJ8mKDqtzXHkvI2b9KzWFhj1OB0R
&state=35725

CODE=PA3VYznHKbwZrSSHAyRy-bWAdSJj-cRUouZu3GoTu-OCC6HUmbPIlAiMH0mSAd8AHOMxf3xycKemTrBTPVWPjhDs0yBFC6608O0fbhz5gACcT64GLw7x622mmHR9W5VU
curl -k https://reader:secret-reader@localhost:8443/oauth2/token \
 -d grant_type=authorization_code \
 -d client_id=reader \
 -d redirect_uri=https://my.redirect.uri \
 -d code=$CODE -s | jq .


{
  "access_token": "eyJraWQiOiJmZDE5NWJjNS04OWM5LTQ4ZmQtYjYzMS1lNjU5MDA4Mjc2OWIiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1IiwiYXVkIjoicmVhZGVyIiwibmJmIjoxNzQ1MzEwNjcxLCJzY29wZSI6WyJwcm9kdWN0OnJlYWQiXSwiaXNzIjoiaHR0cDovL2F1dGgtc2VydmVyOjk5OTkiLCJleHAiOjE3NDUzMTQyNzEsImlhdCI6MTc0NTMxMDY3MX0.SAqKCJNWj1QXjvv-mTCaFuvsriwVnhOmSOJSIHcg4u271pIzTYsbSNgxH_YRPuJ9jaX_DD56mlDOIrN5lLGKqzgxCVnt4weLu39S4wYVsSRA1Zy-O_CQDUYfm_tAZJnlaKesfPsmRrYXJQdXa8fznxFqAtj-NvklOy6bHjJ6iqaYCyIDvT0SEu17z5XV4VQDGhcPpFo-MmJUVjN43I-ljXN-gOrWbIS_jIuFbD8NHVpP8NvneFnOd1OPGCEnEdY1oFo9LFzNPz8bxS_FM6o6fGZVem_7znjDymfudZrydFIQNXcgyA2uzgDHkq6VvmN_UddtADEqkq-DrOJJPFZRaQ",
  "refresh_token": "e6_kHbjkD2wh6oiMq8Sv2XCivwttiEZ5GmoYCBOXZxlpGBrXHZlIGgrSTJzC_hVWUChMGS7jS_xDIWYXqrBLNqeOVpJVNdq219Y9FzjR7xwUHMbYYsdt8UBDoefOePGG",
  "scope": "product:read",
  "token_type": "Bearer",
  "expires_in": 3599
}

# code grant flow for writer
https://localhost:8443/oauth2/authorize?response_type=code&client_id=writer&redirect_uri=https://my.redirect.uri&scope=product:read+product:write&state=72489
https://my.redirect.uri/?code=mfatnPnmF_rqkNcRhTVqJwuzaQR915BPffuxMykEb6hU_1AK63enB8mKm4VZOT86Ci6_oh04NPi5WDCKcENC4J7K8TR7vLp9ZclxJbpWBS0EDCIH4sUwnPPw-AdBUiN3
&state=72489

CODE=KZmW7_QY8W2nbrjr8NOpf3t06cz-ixLATqxB3va9mDpyrIQ7Jn4-WdOK8DdaWuFaWNva9lKLjbAhh_c-Rqk8U9eRVzQRrE74PkWUw37pKu-VVpCgPa2_7pha8UwNbFpX
curl -k https://writer:secret-writer@localhost:8443/oauth2/token \
  -d grant_type=authorization_code \
  -d client_id=writer \
  -d redirect_uri=https://my.redirect.uri \
  -d code=$CODE -s | jq .

{
  "access_token": "eyJraWQiOiJmZDE5NWJjNS04OWM5LTQ4ZmQtYjYzMS1lNjU5MDA4Mjc2OWIiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1IiwiYXVkIjoid3JpdGVyIiwibmJmIjoxNzQ1MzEyMTQ1LCJzY29wZSI6WyJwcm9kdWN0OndyaXRlIiwicHJvZHVjdDpyZWFkIl0sImlzcyI6Imh0dHA6Ly9hdXRoLXNlcnZlcjo5OTk5IiwiZXhwIjoxNzQ1MzE1NzQ1LCJpYXQiOjE3NDUzMTIxNDV9.IsfiN9OsH3XWYsdXiG1jDhlnzuk0OVO5GGUagVUWgWSaPfNVnbsLPzFyRgeliAnGvPZi8CV0t4KoegGCS9tLEmu1vFrvQPpeSjIpCD8KNb5l2eVP1oXIYJrcgzLhdkeJ-EcJ9LTKa3oiuIMKiLCne49uuIAaTUR0nisU_3gADNaMrBWkGX1D6uuNYEYI3iz6CHPvSZjUiTLApvOHubT80WZRKf8r1PGDBCx0rlT4cjxe5ucXHIWRhFT5ZXyDbbjEDcpwEQb1Jgz5pwbl9Dzxm1Z9Dsp3yj7A6eE3hTn7WFjq6ufHv__kWUBSp8RP3s2lZuWI3nOu_GLJaknAYGnHJg",
  "refresh_token": "k5R05eKRky5v91IUaDluqDg1WzeLZY3k89v7wxs1r8j-wu-DKasT5OrWlfTXF1dzVV9zbXYyVGO4GQAmBmR2Y6KBQwLzbPb0fYyqSvZgsLDWP3TyvvdYyXTYLmN7Gyna",
  "scope": "product:write product:read",
  "token_type": "Bearer",
  "expires_in": 3599
}

# invalid access
ACCESS_TOKEN=an-invalid-token
curl https://localhost:8443/product-composite/1 -k -H "Authorization: Bearer $ACCESS_TOKEN" -i

# valid access_token
ACCESS_TOKEN=eyJraWQiOiJmZDE5NWJjNS04OWM5LTQ4ZmQtYjYzMS1lNjU5MDA4Mjc2OWIiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1IiwiYXVkIjoicmVhZGVyIiwibmJmIjoxNzQ1MzEwNjcxLCJzY29wZSI6WyJwcm9kdWN0OnJlYWQiXSwiaXNzIjoiaHR0cDovL2F1dGgtc2VydmVyOjk5OTkiLCJleHAiOjE3NDUzMTQyNzEsImlhdCI6MTc0NTMxMDY3MX0.SAqKCJNWj1QXjvv-mTCaFuvsriwVnhOmSOJSIHcg4u271pIzTYsbSNgxH_YRPuJ9jaX_DD56mlDOIrN5lLGKqzgxCVnt4weLu39S4wYVsSRA1Zy-O_CQDUYfm_tAZJnlaKesfPsmRrYXJQdXa8fznxFqAtj-NvklOy6bHjJ6iqaYCyIDvT0SEu17z5XV4VQDGhcPpFo-MmJUVjN43I-ljXN-gOrWbIS_jIuFbD8NHVpP8NvneFnOd1OPGCEnEdY1oFo9LFzNPz8bxS_FM6o6fGZVem_7znjDymfudZrydFIQNXcgyA2uzgDHkq6VvmN_UddtADEqkq-DrOJJPFZRaQ
curl https://localhost:8443/product-composite/1 -k -H "Authorization: Bearer $ACCESS_TOKEN" -i

curl https://localhost:8443/product-composite/999 -k -H "Authorization: Bearer $ACCESS_TOKEN" -X DELETE -i


# Pour le swagger-ui
https://localhost:8443/openapi/swagger-ui/index.html


