#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Check that kubectl is in the PATH and that it is properly configure to access the
# K8s cluster.
if ! kubectl get ns >>/dev/null; then
    echo "Error: The K8s cluster has not been configured properly. Exiting..."
    exit 1
fi

setup_namespace() {
    # Create test namespace
    #
    # Arguments
    # $1: Namespace to run the tests

    namespace=$1

    echo "Setting up test namespace"
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
}

tear_down() {
    # Tear down test namespace
    #
    # Arguments:
    # $1: Namespace

    namespace=$1
    echo "Tearing down resources"
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo "Deleting namespace $namespace..."
        kubectl delete namespace "$namespace" --wait=true
        echo "Cleanup complete."
    else
        echo "Namespace $namespace already gone."
    fi
}

tear_down_failure() {
    # Tear down and exit 1.
    #
    # Arguments:
    # $1: Namespace

    namespace=$1
    tear_down $namespace
    exit 1
}

create_s3_creds_secret() {
    # Create the S3 credentials secret.
    #
    # Arguments:
    # $1: Namespace that contains the pod

    namespace=$1
    kubectl -n "${namespace}" create secret generic polaris-s3-credentials \
        --from-literal=aws-access-key-id="${ACCESS_KEY:?Set ACCESS_KEY}" \
        --from-literal=aws-secret-access-key="${SECRET_KEY:?Set SECRET_KEY}" \
        --from-literal=aws-region="${AWS_REGION:-us-east-1}"
}

create_db_creds_secret() {
    # Create the DB credentials secret.
    #
    # Arguments:
    # $1: Namespace that contains the pod

    namespace=$1
    kubectl -n "${namespace}" create secret generic polaris-db-credentials \
        --from-literal=db-host="${DB_HOST:?Set DB_HOST}" \
        --from-literal=db-user="${DB_USER:?Set DB_USER}" \
        --from-literal=db-password="${DB_PASSWORD:?Set DB_PASSWORD}" \
        --from-literal=db-name="${DB_NAME:?Set DB_NAME}" \
        --from-literal=jdbc-url="jdbc:postgresql://${DB_HOST}/${DB_NAME}"
}

wait_for_pod_by_label() {
    # Wait for the given pod in the given namespace to be ready.
    #
    # Arguments:
    # $1: (Unique) label of the pod
    # $2: Namespace that contains the pod

    label=$1
    namespace=$2

    echo "Waiting for pod with label '$label' to become ready..."
    kubectl wait --for=condition=Ready pod -l $label -n $namespace --timeout=120s || return 1
}
