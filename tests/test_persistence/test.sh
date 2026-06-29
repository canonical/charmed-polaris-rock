#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set -eu

source ./tests/utils/k8s_utils.sh
source ./tests/utils/polaris_utils.sh

NAMESPACE="test-polaris"

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

restart_polaris() {
    # Restart polaris.
    echo "Restarting polaris..."
    kubectl rollout restart deployment/polaris -n "$NAMESPACE"
    kubectl rollout status --timeout=60s deployment/polaris -n "$NAMESPACE"
    wait_for_pod_by_label app=polaris "$NAMESPACE"
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
        create_catalog &&
        verify_catalog
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
