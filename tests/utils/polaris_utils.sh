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

