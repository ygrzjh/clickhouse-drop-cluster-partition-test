# 配置2分片Clickhouse
.PHONY: config
config:
	rm -rf clickhouse01 clickhouse02
	mkdir -p clickhouse01 clickhouse02
	mkdir -p clickhouse01/config.d clickhouse02/config.d

	cp config.xml clickhouse01/config.xml
	cp config.xml clickhouse02/config.xml
	
	REPLICA=01 SHARD=01 envsubst < metrika.xml > clickhouse01/config.d/metrika.xml
	REPLICA=02 SHARD=02 envsubst < metrika.xml > clickhouse02/config.d/metrika.xml

	REPLICA=01 SHARD=01 envsubst < macros.xml > clickhouse01/config.d/macros.xml
	REPLICA=02 SHARD=02 envsubst < macros.xml > clickhouse02/config.d/macros.xml

	cp users.xml clickhouse01/users.xml
	cp users.xml clickhouse02/users.xml

# 启用2分片Clickhouse
.PHONY: up
up:
	docker-compose up -d

# 启动2分片Clickhouse
.PHONY: start
start:
	docker-compose start

# 停用2分片Clickhouse
.PHONY: down
down:
	docker-compose down

# 清除集群
.PHONY: clean
clean:
	docker-compose down
	rm -rf clickhouse01 clickhouse02