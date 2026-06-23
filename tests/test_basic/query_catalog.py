import os

import polars as pl

from polaris_client import get_catalog

catalog = get_catalog()
table = catalog.load_table("analytics.user_conversions")

df = (
    pl.scan_iceberg(
        table,
        storage_options={
            "aws_access_key_id": os.environ["ACCESS_KEY"],
            "aws_secret_access_key": os.environ["SECRET_KEY"],
            "aws_endpoint_url": os.environ["S3_ENDPOINT"],
            "region": os.environ.get("AWS_REGION", "us-east-1"),
            "aws_virtual_hosted_style_request": "false",
        },
    )
    .collect()
    .sort("id")
)

rows = df.to_dicts()
expected = [
    {"id": 1, "name": "Alice", "value": 100},
    {"id": 2, "name": "Bob", "value": 200},
    {"id": 3, "name": "Charlie", "value": 300},
]

if rows != expected:
    raise SystemExit(f"Unexpected rows: {rows}")

print(df)
