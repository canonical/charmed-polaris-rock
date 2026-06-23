#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set -eu

source ./tests/utils/k8s_utils.sh
source ./tests/utils/polaris_utils.sh

NAMESPACE="test-polaris"
CATALOG_NAME="warehouse"
CATALOG_ROLE="catalog_admin"
PYTHON_BIN=${PYTHON_BIN:-$PWD/.venv-tests/bin/python3}

deploy_polaris() {
    # Deploy polaris.
    export NAMESPACE
    export IMAGE=$(just get-oci)

    echo "Deploying polaris..."
    envsubst <tests/test_persistence/polaris.yaml.templ | kubectl apply -f -
    kubectl wait --for=condition=Available --timeout=60s deploy/polaris -n ${NAMESPACE} || exit 1
    kubectl rollout status --timeout=60s deploy/polaris -n ${NAMESPACE}
}

bootstrap_metastore() {
    # Bootstrap the Polaris metastore.
    pod=$(kubectl -n "$NAMESPACE" get pod -l app=polaris -o jsonpath='{.items[0].metadata.name}')

    echo "Bootstrapping polaris metastore..."
    kubectl exec -n "$NAMESPACE" "$pod" -- \
        /opt/polaris/bin/admin bootstrap -r POLARIS -c "POLARIS,root,s3cr3t"
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

    verify_catalog
}

restart_polaris() {
    # Restart polaris.
    echo "Restarting polaris..."
    kubectl rollout restart deployment/polaris -n "$NAMESPACE"
    kubectl rollout status --timeout=60s deployment/polaris -n "$NAMESPACE"
    wait_for_pod_by_label app=polaris "$NAMESPACE"
}

query_catalog() {
    # Create and query an Iceberg table.
    echo "Creating and querying table..."
    export POLARIS_HOST=$(get_polaris_host "$NAMESPACE")
    "$PYTHON_BIN" tests/resources/populate_catalog.py
    "$PYTHON_BIN" tests/resources/query_catalog.py
}

### TESTS ###

echo -e "##################################"
echo -e "DEPLOY POLARIS"
echo -e "##################################"

(
    setup_namespace $NAMESPACE &&
        create_s3_creds_secret $NAMESPACE &&
        create_db_creds_secret $NAMESPACE &&
        deploy_polaris
) || tear_down_failure $NAMESPACE

echo -e "##################################"
echo -e "CREATE_CATALOG"
echo -e "##################################"

(
    bootstrap_metastore &&
        create_catalog
) || tear_down_failure $NAMESPACE

echo -e "##################################"
echo -e "REDEPLOY POLARIS"
echo -e "##################################"

(
    restart_polaris &&
        verify_catalog
) || tear_down_failure $NAMESPACE

echo -e "##################################"
echo -e "QUERY CATALOG"
echo -e "##################################"

(
    query_catalog &&
        tear_down $NAMESPACE
) || tear_down_failure $NAMESPACE
