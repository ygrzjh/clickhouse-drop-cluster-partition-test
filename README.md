# ClickHouse Cluster
Clickhouse cluster with 2 shards and 1 replicas built with docker-compose.

Clickhouse version: `22.8.5.29`

Cluster xml config
```xml
<clickhouse>
    <remote_servers>
        <default>
            <shard>
                <replica>
                    <host>clickhouse01</host>
                    <port>9000</port>
                </replica>
            </shard>
            <shard>
                <replica>
                    <host>clickhouse02</host>
                    <port>9000</port>
                </replica>
            </shard>
        </default>
    </remote_servers>
</clickhouse>
```
## Run
Run single command, and it will copy configs for each node and
run clickhouse cluster `logs` with docker-compose
```shell
make config up
```

## Test it
Symptom: drop partition on replicated database cluster sql(e.g: `ALTER TABLE demo.test ON CLUSTER 'demo' DROP PARTITION '0';`) only executed on the local clickhouse node,not distributed to the cluster.

- Crate demo replicated database
```sql
-- Crate demo replicated database
set allow_experimental_database_replicated = 1;
CREATE DATABASE demo on cluster 'default'
ENGINE = Replicated('/clickhouse/default/demo', '{shard}', '{replica}');
```

- Query Clusters Info
```sql
-- System Clusters Info
SELECT *
FROM system.clusters
```
> Query Result:
```
┌─cluster─┬─shard_num─┬─shard_weight─┬─replica_num─┬─host_name────┬─host_address─┬─port─┬─is_local─┬─user────┬─default_database─┬─errors_count─┬─slowdowns_count─┬─estimated_recovery_time─┐
│ default │         1 │            1 │           1 │ clickhouse01 │ 172.23.0.11  │ 9000 │        0 │ default │                  │            0 │               0 │                       0 │
│ default │         2 │            1 │           1 │ clickhouse02 │ 172.23.0.12  │ 9000 │        1 │ default │                  │            0 │               0 │                       0 │
│ demo    │         1 │            1 │           1 │ clickhouse01 │ 172.23.0.11  │ 9000 │        0 │ default │                  │            0 │               0 │                       0 │
│ demo    │         2 │            1 │           1 │ clickhouse02 │ 172.23.0.12  │ 9000 │        1 │ default │                  │            0 │               0 │                       0 │
└─────────┴───────────┴──────────────┴─────────────┴──────────────┴──────────────┴──────┴──────────┴─────────┴──────────────────┴──────────────┴─────────────────┴─────────────────────────┘
```

- Create ReplicatedMergeTree engine table and init data
```sql
-- Create ReplicatedMergeTree engine table
CREATE TABLE demo.test
(
    `number` UInt64
)
ENGINE = ReplicatedMergeTree()
PARTITION BY (`number`%2)
ORDER BY `number`;
-- Create Distributed table
CREATE TABLE demo.test_all AS demo.test
ENGINE = Distributed('demo', 'demo', 'test');
-- node1 insert test data
INSERT INTO demo.test SELECT *  FROM numbers(0,10);
-- node2 insert test data
INSERT INTO demo.test SELECT *  FROM numbers(10,10);
```

- Query test table parts
```sql
-- Query test table parts
SELECT
    hostname(),
    partition,
    name
FROM cluster('default', 'system', 'parts')
WHERE (database = 'demo') AND (table = 'test');
```
> Query Result:
```text
┌─hostname()───┬─partition─┬─name────┐
│ clickhouse01 │ 0         │ 0_0_0_0 │
│ clickhouse01 │ 1         │ 1_0_0_0 │
└──────────────┴───────────┴─────────┘
┌─hostname()───┬─partition─┬─name────┐
│ clickhouse02 │ 0         │ 0_0_0_0 │
│ clickhouse02 │ 1         │ 1_0_0_0 │
└──────────────┴───────────┴─────────┘
```

- Drop test part on replicated database cluster
```sql
-- Drop test table part on cluster
ALTER TABLE demo.test ON CLUSTER 'demo' DROP PARTITION '0';

/*
clickhouse01 :) ALTER TABLE demo.test ON CLUSTER 'demo' DROP PARTITION '0';

ALTER TABLE demo.test ON CLUSTER demo
    DROP PARTITION '0'

Query id: 66ec1017-742f-4487-9162-ef2e29663431

Ok.

0 rows in set. Elapsed: 0.033 sec.
*/
```
> Drop Query Result(clickhouse02 part 0 not deleted.):
```text
┌─hostname()───┬─partition─┬─name────┐
│ clickhouse01 │ 1         │ 1_0_0_0 │
└──────────────┴───────────┴─────────┘
┌─hostname()───┬─partition─┬─name────┐
│ clickhouse02 │ 0         │ 0_0_0_0 │
│ clickhouse02 │ 1         │ 1_0_0_0 │
└──────────────┴───────────┴─────────┘
```

- Drop test part on default cluster
```sql
-- Drop test part on default cluster
ALTER TABLE demo.test ON CLUSTER 'default' DROP PARTITION '1';

/*
clickhouse01 :) ALTER TABLE demo.test ON CLUSTER 'default' DROP PARTITION '1';
  
ALTER TABLE demo.test ON CLUSTER default
DROP PARTITION '1'

Query id: 76dbaaa1-6b74-4a40-a607-8d123f6202f4

┌─host─────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
│ clickhouse01 │ 9000 │      0 │       │                   1 │                0 │
│ clickhouse02 │ 9000 │      0 │       │                   0 │                0 │
└──────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘

2 rows in set. Elapsed: 0.119 sec.
*/
```
> Drop Query Result(part 1 all shards deleted.):
```text
┌─hostname()───┬─partition─┬─name────┐
│ clickhouse02 │ 0         │ 0_0_0_0 │
└──────────────┴───────────┴─────────┘
```