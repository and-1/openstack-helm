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

#NOTE: Please limit "besteffort" to dev env with mixed hardware computes only
#      For prod env, the target nic should be there, if not, script should error out.
set -ex
{{- if ( has "besteffort" .Values.conf.sriov_init ) }}
set +e
{{- end }}

{{- range $k, $sriov := .Values.network.interface.sriov }}
if [ "x{{ $sriov.num_vfs }}" != "x" ]; then
  echo "{{ $sriov.num_vfs }}" > /sys/class/net/{{ $sriov.device }}/device/sriov_numvfs
else
  #NOTE(portdirect): Many NICs have difficulty creating more than n-1 over their
  # claimed limit, by default err on the side of caution and account for this
  # limitation.
  TOT_NUM_VFS=$(cat /sys/class/net/{{ $sriov.device }}/device/sriov_totalvfs)
  if [[ "$TOT_NUM_VFS" -le "0" ]]; then
    NUM_VFS="$TOT_NUM_VFS"
  else
    if [[ "$((TOT_NUM_VFS - 1 ))" -le "1" ]]; then
      NUM_VFS=1
    else
      NUM_VFS="$((TOT_NUM_VFS - 1 ))"
    fi
  fi
  echo "${NUM_VFS}" > /sys/class/net/{{ $sriov.device }}/device/sriov_numvfs
fi
{{- if $sriov.mtu }}
ip link set dev {{ $sriov.device }} mtu {{ $sriov.mtu }}
{{- end }}
ip link set {{ $sriov.device }} up
ip link show {{ $sriov.device }}


{{- if $sriov.promisc }}
promisc_mode="on"
{{- else }}
promisc_mode="off"
{{- end }}
ip link set {{ $sriov.device }} promisc ${promisc_mode}
#NOTE(portdirect): get the bus that the port is on
NIC_BUS=$(lshw -c network -businfo | awk '/{{ $sriov.device }}/ {print $1}')
#NOTE(portdirect): get first port on the nic
NIC_FIRST_PORT=$(lshw -c network -businfo | awk "/${NIC_BUS%%.*}/ { print \$2; exit }")
#NOTE(portdirect): Enable promisc mode on the nic, by setting it for the 1st port
ethtool --set-priv-flags ${NIC_FIRST_PORT} vf-true-promisc-support ${promisc_mode}
{{- end }}


{{- if ( has "besteffort" .Values.conf.sriov_init ) }}
exit 0
{{ end }}
