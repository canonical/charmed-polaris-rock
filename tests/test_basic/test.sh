#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set -euo pipefail

source ./tests/utils/k8s_utils.sh
source ./tests/utils/polaris_utils.sh

export NAMESPACE="test-polaris"
export CATALOG_NAME="warehouse"
export CATALOG_ROLE="catalog_admin"
PYTHON_BIN=${PYTHON_BIN:-$PWD/.venv-tests/bin/python3}

deploy_polaris() {
    # Deploy polaris.
    #
    # Arguments:
    # $1: Namespace to run the tests
    export NAMESPACE=$1
    export IMAGE=$(just get-oci)

    echo "Deploying polaris..."
    envsubst <tests/test_basic/polaris.yaml.templ | kubectl apply -f -
    kubectl wait --for=condition=Available --timeout=60s deploy/polaris -n ${NAMESPACE} || exit 1
    kubectl rollout status --timeout=60s deploy/polaris -n ${NAMESPACE}
}

polaris_api() {
    # Call the Polaris management API.
    #
    # Arguments:
    # $1: HTTP method
    # $2: API path
    # $3: Optional payload
    # $4: Optional response file
    method=$1
    path=$2
    data=${3:-}
    response=${4:-$(mktemp)}

    if [ -n "$data" ]; then
        curl -s -o "$response" -w "%{http_code}" \
            -X "$method" "${POLARIS_HOST}${path}" \
            -H "Authorization: Bearer ${POLARIS_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Polaris-Realm: POLARIS" \
            -d "$data"
    else
        curl -s -o "$response" -w "%{http_code}" \
            -X "$method" "${POLARIS_HOST}${path}" \
            -H "Authorization: Bearer ${POLARIS_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Polaris-Realm: POLARIS"
    fi
}

expect_http_code() {
    # Check that the API returned an expected status code.
    #
    # Arguments:
    # $1: Response file
    # $2: Actual HTTP code
    # $3+: Expected HTTP codes
    response=$1
    http_code=$2
    shift 2

    for expected in "$@"; do
        if [ "$http_code" = "$expected" ]; then
            return 0
        fi
    done

    cat "$response"
    return 1
}

create_catalog() {
    # Create the Polaris catalog and grants.
    #
    # Arguments:
    # $1: Namespace to run the tests
    namespace=$1
    catalog_name=${CATALOG_NAME:-warehouse}
    catalog_role=${CATALOG_ROLE:-catalog_admin}
    aws_region=${AWS_REGION:-us-east-1}
    s3_path_style=${S3_PATH_STYLE:-true}
    s3_sts_unavailable=${S3_STS_UNAVAILABLE:-true}
    payload=$(mktemp)
    response=$(mktemp)
    role_payload="{\"catalogRole\": {\"name\": \"${catalog_role}\"}}"

    export POLARIS_HOST=$(get_polaris_host "$namespace")
    export POLARIS_TOKEN=$(get_polaris_token "$POLARIS_HOST")

    echo "Configuring polaris..."

    cat >"$payload" <<EOF
{
  "catalog": {
    "type": "INTERNAL",
    "name": "${catalog_name}",
    "properties": {
      "default-base-location": "s3://${BUCKET}/"
    },
    "storageConfigInfo": {
      "storageType": "S3",
      "endpoint": "${S3_ENDPOINT}",
      "pathStyleAccess": ${s3_path_style},
      "stsUnavailable": ${s3_sts_unavailable},
      "region": "${aws_region}",
      "allowedLocations": ["s3://${BUCKET}/"]
    }
  }
}
EOF

    http_code=$(polaris_api POST "/api/management/v1/catalogs" "@${payload}" "$response")
    if [ "$http_code" = "409" ]; then
        http_code=$(polaris_api PUT "/api/management/v1/catalogs/${catalog_name}" "@${payload}" "$response")
    fi
    expect_http_code "$response" "$http_code" 200 201

 #   http_code=$(polaris_api POST "/api/management/v1/catalogs/${catalog_name}/catalog-roles" "$role_payload" "$response")
#     expect_http_code "$response" "$http_code" 200 201 409

#     polaris_api PUT "/api/management/v1/catalogs/${catalog_name}/catalog-roles/${catalog_role}/grants" \
#         '{"grant": {"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}}' >/dev/null

#     polaris_api PUT "/api/management/v1/principal-roles/service_admin/catalog-roles/${catalog_name}" \
#         "$role_payload" >/dev/null

#     curl -sf -X GET "${POLARIS_HOST}/api/management/v1/catalogs/${catalog_name}" \
#         -H "Authorization: Bearer ${POLARIS_TOKEN}" \
#         -H "Polaris-Realm: POLARIS" | jq -e --arg catalog_name "$catalog_name" '.catalog.name == $catalog_name or .name == $catalog_name' >/dev/null
# }

# table_domain() {
#     # Create and query an Iceberg table.
    #
    # Arguments:
    # $1: Namespace to run the tests
    namespace=$1

    echo "Creating and querying table..."
    export POLARIS_HOST=$(get_polaris_host "$namespace")
    "$PYTHON_BIN" tests/test_basic/populate_catalog.py
    "$PYTHON_BIN" tests/test_basic/query_catalog.py
}

### TESTS ###

echo -e "##################################"
echo -e "DEPLOY POLARIS"
echo -e "##################################"

(
    setup_namespace $NAMESPACE &&
        create_s3_creds_secret $NAMESPACE &&
        deploy_polaris $NAMESPACE
) #|| tear_down_failure $NAMESPACE

# echo -e "##################################"
# echo -e "CREATE_CATALOG"
# echo -e "##################################"

# create_catalog $NAMESPACE || tear_down_failure $NAMESPACE

# echo -e "##################################"
# echo -e "QUERY CATALOG"
# echo -e "##################################"

# (
#     table_domain $NAMESPACE &&
#         tear_down $NAMESPACE
# ) || tear_down_failure $NAMESPACE
