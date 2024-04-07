#!/bin/bash
# sui client verify-bytecode-meter 
sui move build --skip-fetch-latest-git-deps
sui client publish --gas-budget 100000000 --force --json --skip-fetch-latest-git-deps > publish_output.json

> .env
jq '.objectChanges[] | select(.objectType=="0x2::package::UpgradeCap") | .objectId' publish_output.json | awk '{print "ORIGINAL_UPGRADE_CAP_ID="$1}' >> .env
jq '.objectChanges[].packageId | select( . != null )' publish_output.json | awk '{print "PACKAGE_ID="$1}'  | sed 's/\"//g' >> .env
sui client gas --json | jq '.[-1].gasCoinId' | awk '{printf "SUI_FEE_COIN_ID=%s\n",$1}'  >> .env
sui client addresses --json > addresses_output.json
jq '.addresses[] | select(.[0] == "admin") | .[1]' addresses_output.json | awk '{printf "ADMIN=%s\n",$1}' | sed 's/\"//g' >> .env
jq '.addresses[] | select(.[0] == "landlord") | .[1]' addresses_output.json | awk '{printf "LANDLORD=%s\n",$1}'  | sed 's/\"//g' >> .env
jq '.addresses[] | select(.[0] == "tenant") | .[1]' addresses_output.json | awk '{printf "TENANT=%s\n",$1}' | sed 's/\"//g' >> .env

cat .env
