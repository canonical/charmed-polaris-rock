#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

source ./tests/utils/k8s_utils.sh

export NAMESPACE="test-polaris"

deploy_polaris() {
    # Deploy polaris
    #
    # Arguments
    # $1: Namespace to run the tests

    export NAMESPACE=$1
    export IMAGE=$(just get-oci)

    envsubst <tests/test_basic/polaris.yaml.templ | kubectl apply -f -
    kubectl wait --for=condition=Available --timeout=60s deploy/polaris -n ${NAMESPACE} || exit 1
    kubectl rollout status --timeout=60s deploy/polaris -n ${NAMESPACE}
}
### TESTS ###

echo -e "##################################"
echo -e "DEPLOY AND RUN"
echo -e "##################################"

(
    setup_namespace $NAMESPACE &&
        create_s3_creds_secret $NAMESPACE &&
        deploy_polaris $NAMESPACE &&
        tear_down $NAMESPACE
) || tear_down_failure $NAMESPACE
