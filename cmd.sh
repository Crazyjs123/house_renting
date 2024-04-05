#!/bin/bash
source .env
export GAS_BUDGET=100000000
export MODULE_NAME="house_renting"

# admin create platform
echo "=============admin create platform============="
sui client switch --address admin
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function new_platform_and_transfer --gas-budget $GAS_BUDGET --json > cmd_output.json
PLATFORM_ID=`jq '.objectChanges[] | select((.objectType // "") | test("::house_renting::RentalPlatform")) | .objectId' cmd_output.json | sed 's/\"//g'`
ADMIN_ID=`jq '.objectChanges[] | select((.objectType // "") | test("::house_renting::Admin")) | .objectId' cmd_output.json | sed 's/\"//g'`
echo "PLATFORM_ID=${PLATFORM_ID}"
echo "ADMIN_ID=${ADMIN_ID}"

# landlord post rental notice,and new a house object
echo "=============landlord post rental notice============="
sui client switch --address landlord
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function post_rental_notice_and_transfer --args $PLATFORM_ID 2000 70 "his house is very beautiful, facing north and south, with ample sunshine and convenient transportation" "https%3A%2F%2Ftse3-mm.cn.bing.net%2Fth%2Fid%2FOIP-C.NUiYPf7aMFhP-ZCEF0C3IgHaEo%3Fw%3D309%26h%3D193%26c%3D7%26r%3D0%26o%3D5%26pid%3D1.7" --gas-budget $GAS_BUDGET --json > cmd_output.json
HOUSE_ID=`jq '.objectChanges[] | select((.objectType // "") | test("::house_renting::House")) | .objectId' cmd_output.json | sed 's/\"//g'`
NOTICE_ID=`jq '.objectChanges[] | select((.objectType // "") | test("::house_renting::RentalNotice")) | .objectId' cmd_output.json | sed 's/\"//g'`
echo "HOUSE_ID=${HOUSE_ID}"
echo "NOTICE_ID=${NOTICE_ID}"

# tenant pay rent and deposit
echo "=============tenant pay rent and pay deposit============="
sui client switch --address tenant
SPLIT_COIN=`sui client gas --json | jq '.[] | select(.mistBalance > 10000) | .gasCoinId ' | sed -n '1p' | sed 's/\"//g'`
GAS=`sui client gas --json | jq '.[] | select(.mistBalance > 10000) | .gasCoinId ' | sed -n '2p' | sed 's/\"//g'`
echo "SPLIT_COIN=${SPLIT_COIN}"
echo "GAS=${GAS}"
sui client split-coin --coin-id $SPLIT_COIN --amounts 3000  --gas-budget $GAS_BUDGET --gas $GAS --json > cmd_output.json
PAY_COIN=`jq -r '.objectChanges[] | select(.objectType=="0x2::coin::Coin<0x2::sui::SUI>" and .type=="created") | .objectId' cmd_output.json`
echo "PAY_COIN=${PAY_COIN}"
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function pay_rent_and_transfer --args $PLATFORM_ID $HOUSE_ID 1 $PAY_COIN --gas-budget $GAS_BUDGET --json > cmd_output.json
LEASE_ID=`jq -r '.objectChanges[] | select((.objectType // "") | test("::house_renting::Lease")) | .objectId' cmd_output.json | sed 's/\"//g'`
echo "LEASE_ID=${LEASE_ID}"

# landlord transfer house to tenant
echo "=============landlord transfer house to tenant============="
sui client switch --address landlord
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function transfer_house_to_tenant --args $LEASE_ID $HOUSE_ID  --gas-budget $GAS_BUDGET --json > cmd_output.json

# rent expires, landlord inspects and submits inspection report
echo "=============landlord inspects and submits inspection report============="
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function landlord_inspect --args $LEASE_ID 3 "The house is moderately damaged and requires a 50% deposit compensation" "https%3A%2F%2Ftse1-mm.cn.bing.net%2Fth%2Fid%2FOIP-C.fMDb-yleUONKRzYptYDp-QHaFT%3Fw%3D257%26h%3D184%26c%3D7%26r%3D0%26o%3D5%26pid%3D1.7" --gas-budget $GAS_BUDGET --json > cmd_output.json
INSPECTION_ID=`jq -r '.objectChanges[] | select((.objectType // "") | test("::house_renting::Inspection")) |  .objectId' cmd_output.json | sed 's/\"//g'`
echo "INSPECTION_ID=${INSPECTION_ID}"

#The platform administrator reviews the inspection report and return a coin of  deposit
echo "=============The platform administrator reviews the inspection report and return a coin of  deposit============="
sui client switch --address admin
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function review_inspection_report --args $PLATFORM_ID $LEASE_ID $INSPECTION_ID 3 $ADMIN_ID --gas-budget $GAS_BUDGET --json > cmd_output.json


#The tenant returns the room to the landlord , receives the deposit
echo "=============The tenant returns the room to the landlord , receives the deposit============="
sui client switch --address tenant
sui client call --package $PACKAGE_ID --module $MODULE_NAME --function transfer_house_to_tenant --args $LEASE_ID $HOUSE_ID --gas-budget $GAS_BUDGET --json > cmd_output.json





