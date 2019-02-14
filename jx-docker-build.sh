$ cat jx-docker-build.sh
#!/usr/bin/env bash
#
# Usage: jx-docker-build.sh VERSION release|do-not-release
#
# This script relies on these environment variables:
#   DOCKER_ORG - docker organization
#   BASE_IMAGE_VERSION - docker organization
#   PUSH       - true|false

set -o errexit
set -o nounset
set -o pipefail

# Retries a command on failure.
# $1 - the max number of attempts
# $2... - the command to run
retry() {
    local -r -i max_attempts="$1"; shift
    local -r cmd="$@"
    local -i attempt_num=1

    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            echo "Attempt $attempt_num failed and there are no more attempts left!"
            return 1
        else
            echo "Attempt $attempt_num failed! Trying again in $attempt_num seconds..."
            sleep $(( attempt_num++ ))
        fi
    done
}

export VERSION=$1
export RELEASE=$2

export PUSH_LATEST=true
#export CACHE=--no-cache
export CACHE=""

export DOCKER_REGISTRY=docker.io

## set the current values
sed -i '' -e "s/FROM_IMAGE:\(.*\)\/builder-\(.*\)/FROM_IMAGE: ${DOCKER_ORG}\/builder-\2/g" skaffold.yaml
sed -i '' "s/FROM_VERSION:.*/FROM_VERSION: ${BASE_IMAGE_VERSION}/g" skaffold.yaml

## generate Dockerfile.slim
cat Dockerfile.common > Dockerfile.slim
cat Dockerfile.slim.commands >> Dockerfile.slim
## generate Dockerfile.full
cat Dockerfile.common > Dockerfile.full
cat Dockerfile.extra.commands >> Dockerfile.full
cat Dockerfile.slim.commands >> Dockerfile.full

## newman depends on nodejs (amongst others), so order is important
BUILDERS="base swift ruby dlang maven maven-32 maven-java11 maven-nodejs go go-maven gradle gradle4 gradle5 nodejs nodejs8x nodejs10x newman aws-cdk python python2 python37 rust scala terraform"
BROKEN="dotnet"
## now loop through the above array
UPDATEBOT_PUSH_STR=""
for i in $BUILDERS; do
  UPDATEBOT_PUSH_STR="${UPDATEBOT_PUSH_STR} jenkinsxio/${i}-base ${VERSION}"
done


if [ "release" == "${RELEASE}" ]; then
  jx step tag --version ${VERSION}
fi

for i in $BUILDERS; do
  echo "building builder-${i}"
  retry 3 skaffold build -f skaffold.yaml -p ${i}
  #docker rmi ${DOCKER_ORG}/builder-${i}:${VERSION}
done

if [ "release" == "${RELEASE}" ]; then
  updatebot push-version --kind helm ${UPDATEBOT_PUSH_STR}
  updatebot push-regex -r "builderTag: (.*)" -v ${VERSION} jx-build-templates/values.yaml
  updatebot push-regex -r "\s+tag: (.*)" -v ${VERSION} --previous-line "\s+repository: jenkinsxio/builder-go" values.yaml
fi
