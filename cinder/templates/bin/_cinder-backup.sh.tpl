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
set -ex

# Added by Andrey.Fedyunin
cat<<EOF>/tmp/cinder-AZ.conf
[DEFAULT]
backup_ceph_pool = $pool
EOF
backup_az=$(echo $AZ | awk -F\- '{print $2}')
if [ -n "$backup_az" ];then
  cat<<EOF>>/tmp/cinder-AZ.conf
storage_availability_zone = ${backup_az}
host = cinder-volume-worker-${backup_az}
EOF
fi
# End


exec cinder-backup \
     --config-file /etc/cinder/cinder.conf \
     --config-file /tmp/cinder-AZ.conf
