#!/bin/bash

# This script will replace the stemcell on a vagrant box with one that has a
# copy of configgin built from the current directory.  This is (obviously) only
# meant as a testing tool.

# Pre-requisites:
# - SCF checkout (preferably in ../scf, override in $REPO)
# - vagrant VM running for that checkout
# - docker daemon running on the host (requires volumes)

set -o errexit -o nounset

: "${HELM:=helm}"
: "${REPO:=../scf}"

REPO="$( cd "${REPO}" && echo "${PWD}" )"
IMAGE="$( cd "${REPO}" && source .envrc && echo "${FISSILE_STEMCELL}" )"

name="${IMAGE%%:*}"
tag="${IMAGE##*:}"

unset container
unset KUBECONFIG

cleanup() {
    if test -n "${container:-}" ; then
        docker rm -f "${container}"
    fi
    if test -n "${KUBECONFIG:-}" ; then
        rm -f  "${KUBECONFIG}"
    fi
}
trap cleanup EXIT

# Force use the vagrant kubectl context
export KUBECONFIG="$(mktemp)"
kubectl config set-cluster vagrant --server=http://cf-dev.io:8080
kubectl config set-context vagrant --cluster=vagrant --user=""
kubectl config use-context vagrant

vagrant_ready=""
if test -z "${NO_RUN:-}" ; then
    if ( cd "${REPO}" && (vagrant status 2>/dev/null | grep --quiet running) ) ; then
        vagrant_ready="true"
        releases=$("${HELM}" list --short)
        if test -n "${releases}" ; then
            "${HELM}" delete --purge ${releases}
        fi
        kubectl delete ns cf ||:
        kubectl delete ns uaa ||:
    fi
fi

if test -z "$(docker images --quiet "${name}:${tag}-orig" 2>/dev/null)" ; then
    docker pull "${IMAGE}"
    container=$(docker run --detach "${IMAGE}" /bin/bash -c "sleep 1d")
    docker exec -t "${container}" zypper install -y git
    docker commit "${container}" "${name}:${tag}-orig"
fi

container=$(docker run \
    --volume "${PWD}:/src" \
    --detach \
    "${name}:${tag}-orig" \
    /bin/bash -c "sleep 1d")
docker exec -t "${container}" /bin/bash -c "source /usr/local/rvm/scripts/rvm && make -C /src all"
docker exec -t "${container}" /bin/bash -c "source /usr/local/rvm/scripts/rvm && gem install /src/configgin-*.gem"
docker commit "${container}" "${IMAGE}"

test -z "${NO_RUN:-}" || exit

if command -v docker-credential-osxkeychain >/dev/null 2>/dev/null ; then
    docker_user=$(docker-credential-osxkeychain list | jq -r '."https://index.docker.io/v1/"')
else
    docker_user=$(docker system info | awk -F: '{ if ($1 == "Username") { print  $2} }' | tr -d '[:space:]' ||:)
fi

if test -z "${docker_user:-}" ; then
    echo "Can't determine docker user. Are you logged in?"
    exit
fi

docker tag "${IMAGE}" "${docker_user}/${name##*/}:${tag}"
docker push "${docker_user}/${name##*/}:${tag}"

test -n "${vagrant_ready}" || exit

cd "${REPO}"

vagrant ssh -- -tt <<EOF
    set -o errexit -o nounset
    docker pull ${docker_user}/${name##*/}:${tag}
    docker tag ${docker_user}/${name##*/}:${tag} ${IMAGE}
    cd scf
    source .envrc
    while kubectl get namespace cf >/dev/null 2>/dev/null ; do
        sleep 1
    done
    while kubectl get namespace uaa >/dev/null 2>/dev/null ; do
        sleep 1
    done
    docker images --format={{.Repository}}:{{.Tag}} | \
        grep -E '/scf-|uaa-|role-packages' | \
        xargs --no-run-if-empty docker rmi -f
    docker images | \
        awk '/<none>/ { print \$3 }' | \
        xargs --no-run-if-empty docker rmi -f || \
        :
    make compile images helm kube run </dev/null
    exit 0
EOF
