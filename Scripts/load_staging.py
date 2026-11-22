"""Incrementally load the PortWatch CSV files into the staging schema on the SQL Server VM.

Three datasets are supported (choose one with --dataset, or load all of them):

    daily         Daily_Chokepoints_Data__1_.csv   -> staging.portwatch_daily_chokepoints
                  one row per (date, portid): daily vessel counts and capacity per chokepoint
    chokepoints   PortWatch_chokepoints_database.csv -> staging.portwatch_chokepoints
                  one row per portid: the 28 chokepoints with location and yearly totals
    disruptions   portwatch_disruptions_database_*.csv -> staging.portwatch_disruptions
                  one row per eventid: natural disasters (cyclones, floods, ...) and affected ports

Every CSV column is loaded as NVARCHAR text, exactly as it appears in the file.
Type casting and cleaning happen later in dbt (the bronze layer).

The tables are append-only and keep history. On each run, every CSV row is compared
with the latest stored version of the same key (by a hash of its values):
    new        key not in the table yet               -> inserted
    changed    values differ from the latest version  -> inserted as a new version
    unchanged  values identical to the latest version -> skipped
Running the same file twice therefore inserts nothing.

The key is one column for chokepoints (portid) and disruptions (eventid), and two columns
for daily (date + portid). The ArcGIS row number "ObjectId" is NOT part of the hash: it is
just a counter assigned by the export and can change between downloads even when the data
has not, which would otherwise show up as thousands of fake "changed" rows. It is still
loaded as a normal column.

Each row also gets audit columns: _row_id, _loaded_at, _batch_id, _source_file and
_row_hash. All rows inserted by one run share one _loaded_at and are committed in a
single transaction, so a batch is either fully visible or not there at all.

The run stops before writing anything if the CSV has a duplicate or empty key, a value
longer than the column allows, or columns that differ from the existing table.
If the connection drops, the run is retried (it is safe to repeat).

Rows are sent as JSON and unpacked with OPENJSON, which needs SQL Server compatibility
level 130 or higher.

Connection details come from the same environment variables as profiles.yml:
    DBT_SQLSERVER_HOST, DBT_SQLSERVER_USER, DBT_SQLSERVER_PASSWORD

Usage (from the repository root, with .venv-dbt activated):
    python scripts/load_staging_portwatch.py --dataset daily --limit 1000   # quick test run
    python scripts/load_staging_portwatch.py --dataset all                  # load all three files
    python scripts/load_staging_portwatch.py --dataset disruptions --csv path/to/file.csv

The CSV files are not in git; place them in the repository root, or pass the path
with --csv (only allowed together with a single --dataset).
"""

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

import pyodbc

REPO_ROOT = Path(__file__).resolve().parent.parent

DATABASE = "global_shipping_dw"
SCHEMA = "staging"
COLUMN_TYPE_LENGTH = 1000  # longest value in the files is 361 characters (affectedports)
KEY_TYPE_LENGTH = 255  # key columns are indexed, so they stay narrower (index key limit is 1700 bytes)
HASH_LENGTH = 64  # SHA-256 as hex
AUDIT_COLUMNS = ["_row_id", "_loaded_at", "_batch_id", "_source_file", "_row_hash"]
INCOMING = "#incoming"  # temporary table holding the CSV rows during a run
CONNECTION_ATTEMPTS = 3
RETRY_WAIT_SECONDS = 15


@dataclass(frozen=True)
class Dataset:
    table: str
    default_csv: str
    key_columns: tuple[str, ...]
    ignore_in_hash: tuple[str, ...] = field(default=("ObjectId",))


DATASETS = {
    "daily": Dataset(
        table="portwatch_daily_chokepoints",
        default_csv="Daily_Chokepoints_Data__1_.csv",
        key_columns=("date", "portid"),
    ),
    "chokepoints": Dataset(
        table="portwatch_chokepoints",
        default_csv="PortWatch_chokepoints_database.csv",
        key_columns=("portid",),
    ),
    "disruptions": Dataset(
        table="portwatch_disruptions",
        default_csv="portwatch_disruptions_database_-3978591324501330360.csv",
        key_columns=("eventid",),
    ),
}


def quote(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def connect() -> pyodbc.Connection:
    missing = [
        name
        for name in ("server_address", "server_user_name", "server_password")
        if not os.environ.get(name)
    ]
    if missing:
        sys.exit(f"Missing environment variables: {', '.join(missing)}")

    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={os.environ['server_address']},1433;"
        f"DATABASE={DATABASE};"
        f"UID={os.environ['server_user_name']};"
        f"PWD={{{os.environ['server_password'].replace('}', '}}')}}};"
        "Encrypt=yes;TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str, timeout=30)


def column_length(column: str, key_columns: tuple[str, ...]) -> int:
    return KEY_TYPE_LENGTH if column in key_columns else COLUMN_TYPE_LENGTH


def table_columns(cursor: pyodbc.Cursor, table: str) -> list[str]:
    rows = cursor.execute(
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION",
        SCHEMA,
        table,
    ).fetchall()
    return [row[0] for row in rows]


def column_definitions(columns: list[str], key_columns: tuple[str, ...]) -> str:
    return ",\n    ".join(
        f"{quote(col)} NVARCHAR({column_length(col, key_columns)}) NULL" for col in columns
    )


def ensure_table(cursor: pyodbc.Cursor, table: str, columns: list[str], key_columns: tuple[str, ...]) -> bool:
    """Create the table on the first run; on later runs check the columns still match.

    Returns True if the table was created.
    """
    existing = table_columns(cursor, table)

    if existing:
        expected = [c for c in existing if c not in AUDIT_COLUMNS]
        if set(expected) != set(columns):
            sys.exit(
                f"CSV columns do not match [{SCHEMA}].[{table}]. "
                f"Missing from CSV: {sorted(set(expected) - set(columns))}. "
                f"Not in table: {sorted(set(columns) - set(expected))}."
            )
        return False

    cursor.execute(f"IF SCHEMA_ID('{SCHEMA}') IS NULL EXEC('CREATE SCHEMA {quote(SCHEMA)}');")
    cursor.execute(
        f"""CREATE TABLE {quote(SCHEMA)}.{quote(table)} (
    {column_definitions(columns, key_columns)},
    [_row_id] BIGINT IDENTITY(1,1) NOT NULL,
    [_loaded_at] DATETIME2(3) NOT NULL,
    [_batch_id] UNIQUEIDENTIFIER NOT NULL,
    [_source_file] NVARCHAR(255) NOT NULL,
    [_row_hash] CHAR({HASH_LENGTH}) NOT NULL,
    CONSTRAINT {quote('PK_' + table)} PRIMARY KEY CLUSTERED ([_row_id])
);"""
    )
    # Speeds up "find the latest version of this key"
    key_list = ", ".join(quote(c) for c in key_columns)
    cursor.execute(
        f"CREATE INDEX {quote('IX_' + table + '_key')} "
        f"ON {quote(SCHEMA)}.{quote(table)} ({key_list}, [_row_id]);"
    )
    return True


def row_hash(row: list[str | None], hash_order: list[int]) -> str:
    """Fingerprint of a row's data values, independent of CSV column order."""
    payload = json.dumps([row[i] for i in hash_order], ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def stage_csv_rows(
    cursor: pyodbc.Cursor,
    reader,
    columns: list[str],
    dataset: Dataset,
    batch_size: int,
    limit: int | None,
) -> int:
    """Copy CSV rows (plus their hash) into the temporary table. Returns the row count."""
    key_columns = dataset.key_columns
    cursor.execute(
        f"CREATE TABLE {INCOMING} (\n    {column_definitions(columns, key_columns)},\n"
        f"    [_row_hash] CHAR({HASH_LENGTH}) NOT NULL\n);"
    )

    # Each batch is sent as ONE JSON string (an array of rows) and unpacked on the server.
    # Binding one NVARCHAR parameter per column with executemany pads every value to
    # full width and was ~16x slower in testing.
    # Note: OPENJSON silently cuts values that do not fit the column, so lengths are
    # checked below instead.
    json_columns = ", ".join(
        f"{quote(col)} NVARCHAR({column_length(col, key_columns)}) '$[{i}]'"
        for i, col in enumerate(columns)
    ) + f", [_row_hash] CHAR({HASH_LENGTH}) '$[{len(columns)}]'"
    insert_sql = (
        f"INSERT INTO {INCOMING} ({', '.join(quote(c) for c in columns)}, [_row_hash]) "
        f"SELECT {', '.join(quote(c) for c in columns)}, [_row_hash] "
        f"FROM OPENJSON(?) WITH ({json_columns})"
    )

    def send(rows: list[list[str | None]]) -> None:
        cursor.execute(insert_sql, json.dumps(rows, ensure_ascii=False, separators=(",", ":")))

    key_indexes = [columns.index(c) for c in key_columns]
    hash_order = sorted(
        (i for i, c in enumerate(columns) if c not in dataset.ignore_in_hash),
        key=lambda i: columns[i],
    )
    limits = [column_length(c, key_columns) for c in columns]
    seen_keys: set[tuple[str, ...]] = set()
    rows_read = 0
    batch = []

    for row in reader:
        if not row:
            continue  # blank line
        if len(row) != len(columns):
            sys.exit(f"Line {reader.line_num}: expected {len(columns)} fields, found {len(row)}")

        # Empty CSV fields become NULL
        values = [value if value != "" else None for value in row]

        for column, value, max_length in zip(columns, values, limits):
            if value is not None and len(value) > max_length:
                sys.exit(
                    f"Line {reader.line_num}: {column} is {len(value)} characters, "
                    f"longer than the {max_length} the table allows"
                )

        key = tuple(values[i] for i in key_indexes)
        if any(part is None for part in key):
            sys.exit(f"Line {reader.line_num}: empty value in key ({', '.join(key_columns)})")
        if key in seen_keys:
            sys.exit(
                f"Line {reader.line_num}: duplicate key ({', '.join(key_columns)}) = {key!r}; "
                f"nothing was loaded"
            )
        seen_keys.add(key)

        batch.append(values + [row_hash(values, hash_order)])
        rows_read += 1

        if len(batch) >= batch_size:
            send(batch)
            batch = []
            print(f"  {rows_read:>9,} rows sent")
        if limit and rows_read >= limit:
            break

    if batch:
        send(batch)

    return rows_read


def load(csv_path: Path, dataset: Dataset, batch_size: int, limit: int | None, table: str | None = None) -> None:
    start = time.time()
    table = table or dataset.table
    key_columns = dataset.key_columns
    target = f"{quote(SCHEMA)}.{quote(table)}"
    keys = [quote(c) for c in key_columns]

    conn = connect()
    conn.autocommit = False
    cursor = conn.cursor()

    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        columns = next(reader)

        if len({c.lower() for c in columns}) != len(columns) or "" in columns:
            sys.exit("CSV header has duplicate or empty column names")
        missing_keys = [c for c in key_columns if c not in columns]
        if missing_keys:
            sys.exit(f"CSV has no {', '.join(missing_keys)} column")

        if ensure_table(cursor, table, columns, key_columns):
            print(f"Created {target} with {len(columns)} data columns")
        conn.commit()

        stage_start = time.time()
        rows_read = stage_csv_rows(cursor, reader, columns, dataset, batch_size, limit)
    stage_seconds = time.time() - stage_start
    print(f"Read {rows_read:,} rows from {csv_path.name} in {stage_seconds:.1f}s ({rows_read / max(stage_seconds, 0.001):,.0f} rows/s)")

    # Compare each incoming row with the LATEST stored version of the same key.
    # Comparing with the latest (not any) version means a change A -> B -> A is still seen.
    latest = f"""WITH latest AS (
    SELECT {', '.join(keys)}, [_row_hash],
           ROW_NUMBER() OVER (PARTITION BY {', '.join(keys)} ORDER BY [_row_id] DESC) AS rn
    FROM {target}
)"""
    join_on = " AND ".join(f"l.{k} = i.{k}" for k in keys)
    join_latest = f"LEFT JOIN latest l ON {join_on} AND l.rn = 1"

    count_before = cursor.execute(f"SELECT COUNT_BIG(*) FROM {target}").fetchval()
    new, changed, unchanged = cursor.execute(
        f"""{latest}
SELECT COALESCE(SUM(CASE WHEN l.[_row_hash] IS NULL THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN l.[_row_hash] <> i.[_row_hash] THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN l.[_row_hash] = i.[_row_hash] THEN 1 ELSE 0 END), 0)
FROM {INCOMING} i {join_latest}"""
    ).fetchone()

    batch_id = str(uuid.uuid4())
    loaded_at = cursor.execute("SELECT CAST(SYSUTCDATETIME() AS DATETIME2(3))").fetchval()
    data_columns = ", ".join(quote(c) for c in columns)
    incoming_columns = ", ".join(f"i.{quote(c)}" for c in columns)
    cursor.execute(
        f"""{latest}
INSERT INTO {target} ({data_columns}, [_loaded_at], [_batch_id], [_source_file], [_row_hash])
SELECT {incoming_columns}, ?, ?, ?, i.[_row_hash]
FROM {INCOMING} i {join_latest}
WHERE l.[_row_hash] IS NULL OR l.[_row_hash] <> i.[_row_hash]""",
        loaded_at,
        batch_id,
        csv_path.name,
    )
    inserted = cursor.rowcount

    count_after = cursor.execute(f"SELECT COUNT_BIG(*) FROM {target}").fetchval()
    if inserted != new + changed or count_after - count_before != inserted:
        conn.rollback()
        sys.exit(
            f"Row count mismatch: expected {new + changed:,} inserts, "
            f"inserted {inserted:,}, table grew by {count_after - count_before:,}. Rolled back."
        )
    conn.commit()
    conn.close()

    print(f"  new        {new:>9,}")
    print(f"  changed    {changed:>9,}")
    print(f"  unchanged  {unchanged:>9,}")
    print(f"Inserted {inserted:,} rows into {target} in {time.time() - start:.1f}s (batch {batch_id})")
    print(f"Row count check passed: {target} has {count_after:,} rows")


def load_with_retry(csv_path: Path, dataset: Dataset, batch_size: int, limit: int | None, table: str | None) -> None:
    # The connection to the VM sometimes drops. A run writes nothing until its final
    # transaction, and rerunning is safe (rows already stored are skipped), so retry.
    for attempt in range(1, CONNECTION_ATTEMPTS + 1):
        try:
            load(csv_path, dataset, batch_size, limit, table)
            return
        except (pyodbc.OperationalError, pyodbc.InterfaceError) as error:
            if attempt == CONNECTION_ATTEMPTS:
                sys.exit(f"Connection failed {CONNECTION_ATTEMPTS} times, giving up: {error}")
            print(f"Connection problem (attempt {attempt}/{CONNECTION_ATTEMPTS}): {error}\nRetrying in {RETRY_WAIT_SECONDS}s...")
            time.sleep(RETRY_WAIT_SECONDS)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dataset", choices=[*DATASETS, "all"], default="all", help="which file to load (default: all)")
    parser.add_argument("--csv", type=Path, help="path to the CSV file (only with a single --dataset)")
    parser.add_argument("--table", help=f"table in the {SCHEMA} schema (only with a single --dataset); use another name to test")
    parser.add_argument("--batch-size", type=int, default=5_000, help="rows sent per round trip")
    parser.add_argument("--limit", type=int, help="read only the first N rows of each file (for testing)")
    args = parser.parse_args()

    names = list(DATASETS) if args.dataset == "all" else [args.dataset]
    if len(names) > 1 and (args.csv or args.table):
        sys.exit("--csv and --table can only be used together with a single --dataset")
    if args.table and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.table):
        sys.exit(f"Invalid table name: {args.table}")

    # Check every file exists before loading anything
    jobs = []
    for name in names:
        dataset = DATASETS[name]
        csv_path = args.csv or REPO_ROOT / dataset.default_csv
        if not csv_path.exists():
            sys.exit(f"CSV not found: {csv_path}")
        jobs.append((name, dataset, csv_path))

    for name, dataset, csv_path in jobs:
        print(f"\n=== {name}: {csv_path.name} -> {SCHEMA}.{args.table or dataset.table} ===")
        load_with_retry(csv_path, dataset, args.batch_size, args.limit, args.table)


if __name__ == "__main__":
    main()