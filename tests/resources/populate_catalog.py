import pyarrow as pa
from pyiceberg.schema import Schema
from pyiceberg.types import LongType, NestedField, StringType

from polaris_client import get_catalog

catalog = get_catalog()
namespace = "analytics"
table_id = f"{namespace}.user_conversions"

if (namespace,) not in catalog.list_namespaces():
    catalog.create_namespace(namespace)

schema = Schema(
    NestedField(1, "id", LongType(), required=True),
    NestedField(2, "name", StringType(), required=False),
    NestedField(3, "value", LongType(), required=False),
)

if catalog.table_exists(table_id):
    table = catalog.load_table(table_id)
else:
    table = catalog.create_table(table_id, schema=schema)

data = pa.table(
    {
        "id": pa.array([1, 2, 3], type=pa.int64()),
        "name": pa.array(["Alice", "Bob", "Charlie"], type=pa.string()),
        "value": pa.array([100, 200, 300], type=pa.int64()),
    },
    schema=pa.schema(
        [
            pa.field("id", pa.int64(), nullable=False),
            pa.field("name", pa.string(), nullable=True),
            pa.field("value", pa.int64(), nullable=True),
        ]
    ),
)

table.append(data)
print(f"Inserted {len(data)} rows into '{table_id}'.")
