#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

CATALOG_NAME=warehouse
CATALOG_ROLE=catalog_admin
PYTHON_BIN=${PYTHON_BIN:-$PWD/.venv-tests/bin/python3}

get_polaris_host() {
    # Get the Polaris service URL.
    #
    # Arguments:
    # $1: Namespace that contains the service
    namespace=$1

    lb_ip=$(kubectl -n "$namespace" get svc polaris -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -z "$lb_ip" ]; then
        lb_ip=$(kubectl -n "$namespace" get svc polaris -o jsonpath='{.spec.clusterIP}')
    fi

    echo "http://${lb_ip}:8181"
}

get_polaris_token() {
    # Get a Polaris OAuth token.
    #
    # Arguments:
    # $1: Polaris service URL
    host=$1

    curl -sf -X POST "${host}/api/catalog/v1/oauth/tokens" \
        -H "Polaris-Realm: POLARIS" \
        -d "grant_type=client_credentials" \
        -d "client_id=root" \
        -d "client_secret=s3cr3t" \
        -d "scope=PRINCIPAL_ROLE:ALL" | jq -r '.access_token'
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
    payload=$(mktemp)
    response=$(mktemp)
    role_payload="{\"catalogRole\": {\"name\": \"${CATALOG_ROLE}\"}}"

    export POLARIS_HOST=$(get_polaris_host "$NAMESPACE")
    export POLARIS_TOKEN=$(get_polaris_token "$POLARIS_HOST")

    echo "Configuring polaris..."

    cat >"$payload" <<EOF
{
  "catalog": {
    "type": "INTERNAL",
    "name": "${CATALOG_NAME}",
    "properties": {
      "default-base-location": "s3://test-bucket/"
    },
    "storageConfigInfo": {
      "storageType": "S3",
      "endpoint": "${S3_ENDPOINT}",
      "pathStyleAccess": true,
      "stsUnavailable": true,
      "region": "us-east-1",
      "allowedLocations": ["s3://test-bucket/"]
    }
  }
}
EOF

    http_code=$(polaris_api POST "/api/management/v1/catalogs" "@${payload}" "$response")
    if [ "$http_code" = "409" ]; then
        http_code=$(polaris_api PUT "/api/management/v1/catalogs/${CATALOG_NAME}" "@${payload}" "$response")
    fi
    expect_http_code "$response" "$http_code" 200 201

    http_code=$(polaris_api POST "/api/management/v1/catalogs/${CATALOG_NAME}/catalog-roles" "$role_payload" "$response")
    expect_http_code "$response" "$http_code" 200 201 409

    polaris_api PUT "/api/management/v1/catalogs/${CATALOG_NAME}/catalog-roles/${CATALOG_ROLE}/grants" \
        '{"grant": {"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}}' >/dev/null

    polaris_api PUT "/api/management/v1/principal-roles/service_admin/catalog-roles/${CATALOG_NAME}" \
        "$role_payload" >/dev/null
}

verify_catalog() {
    # Verify that the Polaris catalog exists.
    response=$(mktemp)
    http_code=

    export POLARIS_HOST=$(get_polaris_host "$NAMESPACE")

    for _ in $(seq 1 12); do
        POLARIS_TOKEN=$(get_polaris_token "$POLARIS_HOST") || {
            sleep 5
            continue
        }
        export POLARIS_TOKEN

        http_code=$(curl -s -o "$response" -w "%{http_code}" \
            -X GET "${POLARIS_HOST}/api/management/v1/catalogs/${CATALOG_NAME}" \
            -H "Authorization: Bearer ${POLARIS_TOKEN}" \
            -H "Polaris-Realm: POLARIS" || true)

        if [ "$http_code" = "200" ] && jq -e --arg catalog_name "$CATALOG_NAME" '.catalog.name == $catalog_name or .name == $catalog_name' "$response" >/dev/null; then
            return 0
        fi

        sleep 5
    done

    cat "$response"
    return 1
}

query_catalog() {
    # Create and query an Iceberg table.
    echo "Creating and querying table..."
    export POLARIS_HOST=$(get_polaris_host "$NAMESPACE")
    "$PYTHON_BIN" tests/resources/populate_catalog.py
    "$PYTHON_BIN" tests/resources/query_catalog.py
}
