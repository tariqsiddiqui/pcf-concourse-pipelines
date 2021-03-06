#!/bin/bash -ex

chmod +x om-cli/om-linux
CMD=./om-cli/om-linux

if [[ -z "$SSL_CERT" ]]; then
DOMAINS=$(cat <<-EOF
  {"domains": ["*.$ISOLATION_SEGMENT_DOMAIN"] }
EOF
)

  CERTIFICATES=`$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$DOMAINS"`

  export SSL_CERT=`echo $CERTIFICATES | jq '.certificate' | tr -d '"'`
  export SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq '.key' | tr -d '"'`

  echo "Using self signed certificates generated using Ops Manager..."

fi

REPLICATOR_NAME=`echo $PRODUCT_IDENTIFIER | cut -d'-' -f4`

if [[ -z "$REPLICATOR_NAME" ]]; then
echo "Setting Isolation Segment properties for non replicated tile"

PRODUCT_PROPERTIES=$(cat <<-EOF
{
  ".isolated_router.static_ips": {
    "value": "$ROUTER_STATIC_IPS"
  },
  ".isolated_diego_cell.executor_disk_capacity": {
    "value": "$CELL_DISK_CAPACITY"
  },
  ".isolated_diego_cell.executor_memory_capacity": {
    "value": "$CELL_MEMORY_CAPACITY"
  },
  ".properties.container_networking.disable.garden_network_pool": {
    "value": "$APPLICATION_NETWORK_CIDR"
  },
  ".isolated_diego_cell.garden_network_mtu": {
    "value": $APPLICATION_NETWORK_MTU
  },
  ".isolated_diego_cell.insecure_docker_registry_list": {
    "value": "$INSECURE_DOCKER_REGISTRY_LIST"
  },
  ".isolated_diego_cell.placement_tag": {
    "value": "$SEGMENT_NAME"
  },
  ".isolated_diego_cell.dns_servers": {
    "value": "$DNS_SERVERS"
  }
}
EOF
)

PRODUCT_RESOURCE_CONFIG=$(cat <<-EOF
{
  "isolated_router": {
    "instance_type": {"id": "$ISOLATED_ROUTER_INSTANCE_TYPE"},
    "instances" : $IS_ROUTER_INSTANCES
  },
  "isolated_diego_cell": {
    "instance_type": {"id": "$DIEGO_CELL_INSTANCE_TYPE"},
    "instances" : $IS_DIEGO_CELL_INSTANCES
  }
}
EOF
)

else

echo "Setting Isolation Segment properties for replicated tile"

PRODUCT_PROPERTIES=$(cat <<-EOF
{
  ".isolated_router_$REPLICATOR_NAME.static_ips": {
    "value": "$ROUTER_STATIC_IPS"
  },
  ".isolated_diego_cell_$REPLICATOR_NAME.executor_disk_capacity": {
    "value": "$CELL_DISK_CAPACITY"
  },
  ".isolated_diego_cell_$REPLICATOR_NAME.executor_memory_capacity": {
    "value": "$CELL_MEMORY_CAPACITY"
  },
  ".properties.container_networking.disable.garden_network_pool": {
    "value": "$APPLICATION_NETWORK_CIDR"
  },
  ".isolated_diego_cell_$REPLICATOR_NAME.garden_network_mtu": {
    "value": $APPLICATION_NETWORK_MTU
  },
  ".isolated_diego_cell_$REPLICATOR_NAME.insecure_docker_registry_list": {
    "value": "$INSECURE_DOCKER_REGISTRY_LIST"
  },
  ".isolated_diego_cell_$REPLICATOR_NAME.placement_tag": {
    "value": "$SEGMENT_NAME"
  },
  ".isolated_diego_cell_$REPLICATOR_NAME.dns_servers": {
    "value": "$DNS_SERVERS"
  }
}
EOF
)

PRODUCT_RESOURCE_CONFIG=$(cat <<-EOF
{
  "isolated_router_$REPLICATOR_NAME": {
    "instance_type": {"id": "$ISOLATED_ROUTER_INSTANCE_TYPE"},
    "instances" : $IS_ROUTER_INSTANCES
  },
  "isolated_diego_cell_$REPLICATOR_NAME": {
    "instance_type": {"id": "$DIEGO_CELL_INSTANCE_TYPE"},
    "instances" : $IS_DIEGO_CELL_INSTANCES
  }
}
EOF
)

fi

function fn_other_azs {
  local azs_csv=$1
  echo $azs_csv | awk -F "," -v braceopen='{' -v braceclose='}' -v name='"name":' -v quote='"' -v OFS='"},{"name":"' '$1=$1 {print braceopen name quote $0 quote braceclose}'
}

BALANCE_JOB_AZS=$(fn_other_azs $OTHER_AZS)

PRODUCT_NETWORK_CONFIG=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$SINGLETON_JOB_AZ"
  },
  "other_availability_zones": [
    $BALANCE_JOB_AZS
  ],
  "network": {
    "name": "$NETWORK_NAME"
  }
}
EOF
)

$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_IDENTIFIER -p "$PRODUCT_PROPERTIES" -pn "$PRODUCT_NETWORK_CONFIG" -pr "$PRODUCT_RESOURCE_CONFIG"

if [[ "$SSL_TERMINATION_POINT" == "terminate_at_router" ]]; then
echo "Terminating SSL at the gorouters and using self signed/provided certs..."
SSL_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "$SSL_TERMINATION_POINT"
  },
  ".properties.networking_point_of_entry.terminate_at_router.ssl_rsa_certificate": {
    "value": {
      "cert_pem": "$SSL_CERT",
      "private_key_pem": "$SSL_PRIVATE_KEY"
    }
  },
  ".properties.networking_point_of_entry.terminate_at_router.ssl_ciphers": {
    "value": "$ROUTER_SSL_CIPHERS"
  }
}
EOF
)

elif [[ "$SSL_TERMINATION_POINT" == "terminate_at_router_ert_cert" ]]; then
echo "Terminating SSL at the gorouters and reusing self signed/provided certs from ERT tile..."
SSL_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "$SSL_TERMINATION_POINT"
  }
}
EOF
)

elif [[ "$SSL_TERMINATION_POINT" == "terminate_before_router" ]]; then
echo "Unencrypted traffic to goRouters as SSL terminated at load balancer..."
SSL_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "$SSL_TERMINATION_POINT"
  }
}
EOF
)

fi

echo "Configuring SSL termiation point ..."

$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_IDENTIFIER -p "$SSL_PROPERTIES"

if [[ "$LOGGING_ENABLED" == "disabled" ]]; then
SYSLOG_PROPERTIES=$(cat <<-EOF
{
  ".properties.system_logging": {
    "value": "$LOGGING_ENABLED"
  }
}
EOF
)
elif [[ "$LOGGING_ENABLED" == "disabled" ]]; then
SYSLOG_PROPERTIES=$(cat <<-EOF
{
  ".properties.system_logging": {
    "value": "$LOGGING_ENABLED"
  },
  ".properties.system_logging.enabled.host": {
    "value": "$SYSLOG_HOST"
  },
  ".properties.system_logging.enabled.port": {
    "value": "$SYSLOG_PORT"
  },
  ".properties.system_logging.enabled.protocol": {
    "value": "$SYSLOG_PROTOCOL"
  },
  ".properties.system_logging.enabled.tls_enabled": {
    "value": "$SYSLOG_TLS_ENABLED"
  },
  ".properties.system_logging.enabled.tls_permitted_peer": {
    "value": "$SYSLOG_TLS_PERMITTED_PEER"
  },
  ".properties.system_logging.enabled.tls_ca_cert": {
    "value": "$SYSLOG_TLS_CA_CERTIFICATE"
  }
}
EOF
)
fi

echo "Configuring syslog ..."

$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_IDENTIFIER -p "$SYSLOG_PROPERTIES"
