# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

import os

from pyiceberg.catalog.rest import RestCatalog


def get_catalog() -> RestCatalog:
    return RestCatalog(
        "polaris",
        **{
            "uri": f"{os.environ['POLARIS_HOST']}/api/catalog",
            "warehouse": os.environ.get("CATALOG_NAME", "warehouse"),
            "credential": "root:s3cr3t",
            "scope": "PRINCIPAL_ROLE:ALL",
            "oauth2-server-uri": f"{os.environ['POLARIS_HOST']}/api/catalog/v1/oauth/tokens",
            "header.Polaris-Realm": "POLARIS",
            "header.X-Iceberg-Access-Delegation": "none",
            "s3.endpoint": os.environ["S3_ENDPOINT"],
            "s3.access-key-id": os.environ["ACCESS_KEY"],
            "s3.secret-access-key": os.environ["SECRET_KEY"],
            "s3.path-style-access": "true",
            "s3.region": os.environ.get("AWS_REGION", "us-east-1"),
        },
    )
