#!/bin/bash -ex

echo "Testing"
PRODUCT_NETWORK=$(
  echo "{}" |
  $JQ_CMD -n \
    --arg network_name "$NETWORK_NAME" \
    '. +
    { 
      "network": {
        "name": $network_name
      }
    }
    '
)

echo "Testing"
echo $PRODUCT_NETWORK
$OM_CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_IDENTIFIER -pn "$PRODUCT_NETWORK" -p "$PRODUCT_PROPERTIES"
