#!/bin/bash -e

DIR="`dirname \"$0\"`"
PODS="mongo-connector-resourcetypes-0 mongo-connector-resources-0 mongo-connector-propertytypes-0"
cd $DIR/../../

if [ ! -d elastic2-doc-manager ]; then
  echo "https://github.com/RiffynInc/elastic2-doc-manager must be checked out to the same directory as mongo-connector, e.g.,"
  echo "  ~/workspace/mongo-connector"
  echo "  ~/workspace/elastic2-doc-manager"
  exit 1
fi

echo "setting kubectl context to minikube"
kubectl config use-context minikube

NON_LOCAL_PODS=$(kubectl get pod $PODS -o custom-columns=:{..containers[*].image} | grep connector | grep -v -e ":local$" | wc -l | tr -d '[:space:]')

if [ $NON_LOCAL_PODS -gt 0 ]; then
  echo "ERROR: You have $NON_LOCAL_PODS connector pods running without the ':local' image tag. "
  echo "  To use this script, you must first stop any running connector pods and then start them with the :local tag"
  echo "  e.g., local-dev.py --start mongo-connector-resources:local"
  exit 2
fi

cd mongo-connector && python setup.py bdist_wheel
cd ../elastic2-doc-manager && python setup.py bdist_wheel
cd ../

tar -zcvf mongo-connector/mongo-elastic.tar mongo-connector/dist/mongo_connector-*.whl elastic2-doc-manager/dist/elastic2_doc_manager-*.whl

# make sure the image gets pushed to the right docker env
eval $(minikube docker-env)
cd mongo-connector && docker build -t riffyninc/mongo-connector:local .

# if tagName doesnt change, restart pods by doing the following:
kubectl delete pod $PODS --grace-period 0 --force
