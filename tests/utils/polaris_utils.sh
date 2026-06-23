#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

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
