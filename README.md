# Percona MySQL server with Percona Tools, Replication Support & Shared Volume Initialization

Run a container:

```
docker run -d --name percona \
  -v /home/docker/percona-data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=mypass \
  -p 3308:3306 \
  klevo/percona
```

## Hot Backups

Hot backup on a running container:

```
docker exec -i -t percona innobackupex /backups
docker exec -i -t percona innobackupex --apply-log /backups/2014-12-16_14-44-35
```

## Replication Over SSH Tunnel

Run a container with replication settings specified:

```
docker run -d --name db1_slave \
  -v /home/docker/percona-data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=mypass \
  -e REPLICATION_SLAVE_MASTER_IP=someip \
  -e REPLICATION_SLAVE_REMOTE_PORT=3306 \
  -e REPLICATION_SLAVE_PASSWORD=slaveuserpass \
  -p 3308:3306 \
  klevo/percona
```

Get SQL for master to set up the replication:

```
docker exec -i -t db1_slave replication_master_sql
```

outputs something like:

```
GRANT REPLICATION SLAVE ON *.* TO 'slave_db1'@'localhost' IDENTIFIED BY 'slaveuserpass';
```

Start replication on the slave (execute this once master was configured with the above sql):

```
docker exec -i -t db1_slave start_replication mysql-bin.000001 107
```

Runs something like this in the background on the slave container:

```
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_USER='slave_db1', MASTER_PASSWORD='slaveuserpass', MASTER_PORT=3307, MASTER_LOG_FILE='mysql-bin.000001', MASTER_LOG_POS=107;
START SLAVE;
```