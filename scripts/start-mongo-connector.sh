#!/bin/bash

OPLOG_TIMESTAMP_LOCATION="/srv/riffyn/mongo-connector/oplogts/oplog.timestamp"

RESET_INDEX=${RESET_INDEX:-0}
#SKIP_INDEX_RESET  : 0: do not reset and 1: reset index
ELASTIC_TIMEOUT=${ELASTIC_TIMEOUT: 30}
ELASTIC_MAX_RETRY=${ELASTIC_MAX_RETRY: 20}
ELASTIC_RETRY_ON_TIMEOUT=${ELASTIC_RETRY_ON_TIMEOUT: 1}

# Ignore warnings 'Unverified HTTPS request'
export PYTHONWARNINGS="ignore:Unverified HTTPS request"

echo " value of RESET_INDEX: ${RESET_INDEX}"
echo " value of ELASTIC_SSL_ENABLED: ${ELASTIC_SSL_ENABLED}"
echo " value of ELASTIC_HOST: ${ELASTIC_HOST}"
echo " value of ELASTIC_PORT: ${ELASTIC_PORT}"
echo " value of ELASTIC_USER: ${ELASTIC_USER}"
echo " value of ELASTIC_PASSWORD: ${ELASTIC_PASSWORD}"
echo " value of MONGO_HOSTS: ${MONGO_HOSTS}"
echo " value of INDEX_NAME: ${INDEX_NAME}"
echo " value of ELASTIC_TIMEOUT: ${ELASTIC_TIMEOUT}"
echo " value of ELASTIC_MAX_RETRY: ${ELASTIC_MAX_RETRY}"
echo " value of ELASTIC_RETRY_ON_TIMEOUT: ${ELASTIC_RETRY_ON_TIMEOUT}"

echo "setting TARGET_URL for elasticsearch"
# default to https unless ELASTIC_SSL_ENABLED is false
if [ $ELASTIC_SSL_ENABLED == "false" ]; then
    ELASTIC_PROTOCOL="http"
else
    ELASTIC_PROTOCOL="https"
fi

TARGET_URL="${ELASTIC_HOST}:${ELASTIC_PORT}"

if [[ -z "${ELASTIC_USERNAME}" &&  -z "${ELASTIC_PASSWORD}" ]]; then
  echo "Elasticsearch username and password undefined proceeding without authentication"
else
  echo "Elasticsearch username and password defined adding to TARGET_URL"
  TARGET_URL="${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}@${ELASTIC_HOST}:${ELASTIC_PORT}"
fi

# check if the index exists. If the index is absent in ES, continue with RESET INDEX flow
# is there a easier way to check if a index is present in ElasticSearch ?
INDEX_CHECK_CURL_COMMAND="curl -k --write-out %{response_code} --silent --output /dev/null ${ELASTIC_PROTOCOL}://${TARGET_URL}/${INDEX_NAME}"
INDEX_CHECK=$($INDEX_CHECK_CURL_COMMAND)
echo "Response code from curl request to check ${INDEX_NAME} = ${INDEX_CHECK}"

if [ $INDEX_CHECK == 200 ];
then
  echo "Index ${INDEX_NAME} already exists"
else
  RESET_INDEX="1"
  echo "Index ${INDEX_NAME} not found on ElasticSearch. Continue with RESET INDEX flow"
fi

# If the oplog.timestamp file does not exists, trigger the reset index flow
if [ ! -f ${OPLOG_TIMESTAMP_LOCATION} ]; then
    RESET_INDEX="1"
    echo "${OPLOG_TIMESTAMP_LOCATION} does not exist. Continue with RESET INDEX flow"
else
    echo "oplog timestamp exists"
    cat "${OPLOG_TIMESTAMP_LOCATION}"
fi

if [ "$RESET_INDEX" == "1" ]
then
    echo "Resetting elasticsearch index ${INDEX_NAME}...."
    bash elasticsearch-configure.sh -f
    echo "Checking to see ${INDEX_NAME} was created...."
    INDEX_CHECK=$($INDEX_CHECK_CURL_COMMAND)
    echo "Response code from curl request to check ${INDEX_NAME} = ${INDEX_CHECK}"
else
    echo "skipping elastic search configure because RESET_INDEX is set to $RESET_INDEX"
fi

MONGO_SSL_ARGS=""

if [ "$MONGO_SSL_ENABLED" == "true" ]
then
    echo "SSL enabled for MongoDB adding SSL args"
    MONGO_SSL_ARGS="--ssl-certfile /etc/ssl/mongodb/client.pem --ssl-certificate-policy ignored"
fi

echo "setting mongo-connector for index ${INDEX_NAME}"

# $MONGO_HOSTS should be in format HOSTNAME:PORT
# example mongodb01:27017,mongodb02:27017,mongodb03:27017

# Use the auto commit interval only if defined
if [ -z "$AUTO_COMMIT_INTERVAL" ]
then
    echo "AUTO_COMMIT_INTERVAL is not defined, using value from connector's config."
    mongo-connector $MONGO_SSL_ARGS -m $MONGO_HOSTS -c "config/connector_${INDEX_NAME}.json" --oplog-ts ${OPLOG_TIMESTAMP_LOCATION}  -t $TARGET_URL --stdout
else
    echo " value of AUTO_COMMIT_INTERVAL : ${AUTO_COMMIT_INTERVAL}"
    mongo-connector --auto-commit-interval=${AUTO_COMMIT_INTERVAL} $MONGO_SSL_ARGS -m $MONGO_HOSTS -c "config/connector_${INDEX_NAME}.json" --oplog-ts ${OPLOG_TIMESTAMP_LOCATION}  -t $TARGET_URL --stdout
fi
#mongo-connector --auto-commit-interval=0 -m $MONGO_HOSTS -c config/connector_${INDEX_NAME}.json --oplog-ts ${OPLOG_TIMESTAMP_LOCATION}/oplog.timestamp -t $ELASTIC_USER:$ELASTIC_PASSWORD@$ELASTIC_HOST:$ELASTIC_PORT --stdout

sleep 10

echo " FINISHED executing mongo-connector.sh "
