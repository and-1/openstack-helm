#!/bin/bash

{{/*
Copyright 2017 The Openstack-Helm Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

set -x
if [ "x$STORAGE_BACKEND" == "xcinder.backup.drivers.ceph" ]; then
  SECRET=$(mktemp --suffix .yaml)
  KEYRING=$(mktemp --suffix .keyring)
  function cleanup {
      rm -f ${SECRET} ${KEYRING}
  }
  trap cleanup EXIT
fi

set -ex
if [ "x$STORAGE_BACKEND" == "xcinder.backup.drivers.swift" ] || \
     [ "x$STORAGE_BACKEND" == "xcinder.backup.drivers.posix" ]; then
  echo "INFO: no action required to use $STORAGE_BACKEND"
elif [ "x$STORAGE_BACKEND" == "xcinder.backup.drivers.ceph" ]; then
  ceph -s
  function ensure_pool () {
    ceph osd pool stats $1 || ceph osd pool create $1 $2
    local test_luminous=$(ceph tell osd.* version | egrep -c "12.2|luminous" | xargs echo)
    if [[ ${test_luminous} -gt 0 ]]; then
      ceph osd pool application enable $1 $3
    fi
    size_protection=$(ceph osd pool get $1 nosizechange | cut -f2 -d: | tr -d '[:space:]')
    ceph osd pool set $1 nosizechange 0
    ceph osd pool set $1 size ${RBD_POOL_REPLICATION}
    ceph osd pool set $1 nosizechange ${size_protection}
    ceph osd pool set $1 crush_rule "${RBD_POOL_CRUSH_RULE}"
  }
# Pools created in ceph-client chart
#  ensure_pool ${RBD_POOL_NAME} ${RBD_POOL_CHUNK_SIZE} "cinder-backup"

  if USERINFO=$(ceph auth get client.${RBD_POOL_USER}); then
    KEYSTR=$(echo $USERINFO | sed 's/.*\( key = .*\) caps mon.*/\1/')
    echo $KEYSTR  > ${KEYRING}
  else
    #NOTE(Portdirect): Determine proper privs to assign keyring
    #NOTE(JCL): Adjusted permissions for cinder backup.
    # relax permissions if AZ enabled
    if [ "x${AZ}" == "xtrue" ];then
      pool_arg=""
    else
      pool_arg="pool=${RBD_POOL_NAME}"
    fi
    ceph auth get-or-create client.${RBD_POOL_USER} \
      mon "profile rbd" \
      osd "profile rbd ${pool_arg}" \
      -o ${KEYRING}
  fi

  ENCODED_KEYRING=$(sed -n 's/^[[:blank:]]*key[[:blank:]]\+=[[:blank:]]\(.*\)/\1/p' ${KEYRING} | base64 -w0)
  cat > ${SECRET} <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: "${RBD_POOL_SECRET}"
type: kubernetes.io/rbd
data:
  key: $( echo ${ENCODED_KEYRING} )
EOF
  kubectl apply --namespace ${NAMESPACE} -f ${SECRET}

fi
