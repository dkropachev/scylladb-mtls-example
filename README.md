# ScyllaDB mTLS Test Environment

A complete development environment for testing ScyllaDB with mutual TLS (mTLS) authentication. This project provides automated certificate generation, cluster management, and a Python-based data loading script.

## Features

- 🔐 **Automatic mTLS Certificate Management** - Single CA with node, client, and user certificates
- 🚀 **One-Command Cluster Setup** - Start a 3-node ScyllaDB cluster with `make start`
- 🐍 **Python Environment via uv** - Fast, modern Python package management
- 📊 **Data Loading Script** - Multi-process parallel data insertion with mTLS
- 🔄 **Idempotent Operations** - Certificates only created if absent
- 🧹 **Easy Cleanup** - Clean certificates, containers, or everything

## Prerequisites

- Docker and Docker Compose
- OpenSSL
- [uv](https://github.com/astral-sh/uv) - Fast Python package installer
- Python 3.12 (default, configurable)

### Installing uv

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or with pip
pip install uv
```

## Quick Start

```bash
# Start the cluster (creates certificates automatically)
make start

# Run the mTLS test script
make run-mtls ROW_COUNT=10000

# Check cluster status
make status

# Stop the cluster
make stop
```

## Architecture

### Cluster Configuration

- **3 ScyllaDB nodes** (scylla-1, scylla-2, scylla-3)
- **Network**: 172.41.0.0/16
- **Node IPs**: 172.41.0.2, 172.41.0.3, 172.41.0.4
- **mTLS Port**: 9142 (native)
- **Shard-aware Port**: 19142 (optional)

### Certificate Structure

```
config/
├── ca/
│   ├── ca.crt          # Root Certificate Authority
│   └── ca.key          # CA private key
├── db/
│   ├── db.crt          # Database client certificate
│   ├── db.key          # Client private key
│   └── ca.crt          # CA certificate (copy)
└── user/
    ├── user.crt        # User client certificate
    ├── user.key        # User private key
    └── ca.crt          # CA certificate (copy)

cluster/
├── scylla-1/
│   ├── db.crt          # Node 1 certificate
│   ├── db.key          # Node 1 private key
│   ├── ca.crt          # CA certificate
│   └── scylla.yaml     # Node configuration
├── scylla-2/
│   └── ...             # Node 2 certificates
└── scylla-3/
    └── ...             # Node 3 certificates
```

**All certificates are signed by the same CA**, enabling mutual trust between nodes and clients.

## Makefile Targets

### Certificate Management

```bash
make ca            # Create Certificate Authority (only if absent)
make node-certs    # Create certificates for all 3 nodes
make db-certs      # Create database client certificates
make user-certs    # Create user client certificate
make certs         # Create all certificates (CA + nodes + clients)
```

### Python Environment

```bash
make venv          # Create Python virtual environment with uv
make install       # Install dependencies (cassandra-driver, faker)
```

### Cluster Operations

```bash
make start         # Start the 3-node ScyllaDB cluster
make stop          # Stop the cluster
make restart       # Restart the cluster (stop + start)
make status        # Show cluster container status
make wait-cluster  # Wait for all nodes to be ready (UN state)
make logs          # Follow cluster logs (Ctrl+C to exit)
```

**Note:** `make run-mtls` automatically calls `wait-cluster` to ensure the cluster is ready before running the script.

### Testing

```bash
make run-mtls      # Run mTLS data loading script (default params)
```

**Parameters:**
- `HOSTS` - Comma-separated node IPs (default: 172.41.0.2)
- `KEYSPACE` - Keyspace name (default: mykeyspace)
- `TABLE` - Table name (default: myTable)
- `ROW_COUNT` - Number of rows to insert (default: 100000)
- `WORKERS` - Number of worker processes (default: 0 = auto-detect CPUs)
- `DC` - Datacenter name (default: datacenter1)

**Examples:**

```bash
# Test with single node, 1000 rows
make run-mtls ROW_COUNT=1000

# Test with all nodes, 50k rows, 4 workers
make run-mtls HOSTS=172.41.0.2,172.41.0.3,172.41.0.4 ROW_COUNT=50000 WORKERS=4

# Test with custom keyspace
make run-mtls KEYSPACE=test TABLE=users ROW_COUNT=5000
```

### Cleanup

```bash
make clean         # Remove containers and volumes
make clean-certs   # Remove all certificates (stops cluster first, WARNING: destructive)
make clean-venv    # Remove Python virtual environment
make clean-all     # Clean everything (containers + certs + venv)
```

**Note:** `make clean-certs` automatically stops the cluster before removing certificates to prevent certificate mismatch issues.

### Help

```bash
make help          # Show all available targets with descriptions
```

## Dependency Chain

The Makefile automatically resolves dependencies:

```
make start
  └─ node-certs (auto-creates if absent)
      └─ ca (auto-creates if absent)

make run-mtls
  ├─ install (auto-creates if needed)
  │   └─ venv (auto-creates if needed)
  ├─ db-certs (auto-creates if absent)
  │   └─ ca (auto-creates if absent)
  └─ wait-cluster (waits for all nodes to be UP and NORMAL)
```

This means you can run `make start` or `make run-mtls` from a clean state, and all prerequisites will be created automatically. The `wait-cluster` target ensures the cluster is fully ready before running scripts.

## Configuration

### Certificate Parameters

Edit these variables in the Makefile to customize certificate generation:

```makefile
PYTHON_VERSION ?= 3.12        # Python version for venv
CA_DAYS := 3650               # CA validity (10 years)
CERT_DAYS := 365              # Certificate validity (1 year)
COUNTRY := US                 # Certificate country
STATE := CA                   # Certificate state
CITY := SanFrancisco          # Certificate city
ORG := ScyllaDB               # Organization name
OU := Testing                 # Organizational unit
```

### Node Configuration

To add/remove nodes or change IPs:

1. Edit `Makefile`:
   ```makefile
   NODES := scylla-1 scylla-2 scylla-3 scylla-4
   NODE_IPS := 172.41.0.2 172.41.0.3 172.41.0.4 172.41.0.5
   ```

2. Update `cluster/docker-compose.yml` with the new node configuration

## mTLS Script Details

The `scripts/mtls.py` script provides:

- **Multi-process parallel insertion** using Python's multiprocessing
- **SSL/TLS 1.2+ with certificate verification**
- **Token-aware load balancing** across cluster nodes
- **Configurable consistency levels** (default: LOCAL_QUORUM)
- **Fake data generation** using the Faker library
- **Progress logging** from worker processes

### Script Usage

```bash
# Direct execution (without make)
.venv/bin/python scripts/mtls.py \
  --hosts 172.41.0.2,172.41.0.3,172.41.0.4 \
  --keyspace mykeyspace \
  --table myTable \
  --row_count 100000 \
  --workers 4 \
  --dc datacenter1 \
  --cl LOCAL_QUORUM
```

### Data Schema

The script creates a table with the following schema:

```sql
CREATE TABLE mykeyspace.myTable (
    id int PRIMARY KEY,
    ssn text,
    imei text,
    os text,
    phonenum text,
    balance float,
    pdate date,
    v1 text,
    v2 text,
    v3 text,
    v4 text,
    v5 text
) WITH compression = {'sstable_compression': 'LZ4Compressor'};
```

## Troubleshooting

### Certificate Issues

**Problem**: Cluster fails to start with certificate errors

```bash
# Check certificate validity
openssl verify -CAfile config/ca/ca.crt cluster/scylla-1/db.crt

# Regenerate all certificates (stops cluster automatically)
make clean-certs
make start
```

**Problem**: Certificate mismatch errors after regenerating certificates

The `clean-certs` target now automatically stops the cluster first to prevent this issue. If you manually regenerate certificates, always restart the cluster afterward:

```bash
# Always restart after manual certificate changes
make restart
```

### Connection Issues

**Problem**: mTLS script cannot connect

```bash
# Check if cluster is ready (all nodes UN)
make wait-cluster

# Check cluster health
make status

# View logs for errors
make logs

# Test SSL connection with openssl
openssl s_client -connect 172.41.0.2:9142 \
  -CAfile config/ca/ca.crt \
  -cert config/db/db.crt \
  -key config/db/db.key
```

**Problem**: Script runs immediately after `make start` and fails

The `make run-mtls` target now automatically waits for the cluster to be ready. If you're running the script manually, use `make wait-cluster` first.

### Docker Issues

**Problem**: Containers fail to start

```bash
# Clean everything and restart
make clean
docker system prune -f
make start
```

### Python Issues

**Problem**: Module not found errors

```bash
# Reinstall dependencies
make clean-venv
make install
```

## Testing the Setup

Complete end-to-end test:

```bash
# 1. Start fresh
make clean-all

# 2. Start cluster (creates certs + starts nodes)
make start

# 3. Wait for cluster to be healthy
make status

# 4. Run test with small dataset
make run-mtls ROW_COUNT=1000 WORKERS=2

# 5. Run test with all nodes
make run-mtls HOSTS=172.41.0.2,172.41.0.3,172.41.0.4 ROW_COUNT=5000

# 6. Check cluster status
make status

# 7. Clean up
make stop
```

## Performance Tips

1. **Use multiple workers** for faster insertion:
   ```bash
   make run-mtls ROW_COUNT=100000 WORKERS=8
   ```

2. **Target multiple nodes** for better load distribution:
   ```bash
   make run-mtls HOSTS=172.41.0.2,172.41.0.3,172.41.0.4
   ```

3. **Use shard-aware port** for optimal performance:
   ```bash
   .venv/bin/python scripts/mtls.py --hosts 172.41.0.2 --shard_aware
   ```

## Security Notes

- ⚠️ This is a **development/testing environment** only
- Certificates use self-signed CA (not suitable for production)
- Private keys are stored unencrypted in the repository (gitignored)
- No password protection on certificates
- Default ScyllaDB credentials (cassandra/cassandra)

For production:
- Use a proper PKI infrastructure
- Store certificates securely (vault, secrets manager)
- Enable certificate revocation lists (CRL)
- Use strong passwords and key encryption
- Rotate certificates regularly

## Project Structure

```
.
├── Makefile              # Automation and orchestration
├── README.md             # This file
├── .gitignore           # Excludes certificates and venv
├── cluster/             # Docker Compose and node configs
│   ├── docker-compose.yml
│   └── scylla-{1,2,3}/  # Per-node configuration
├── config/              # Generated certificates (gitignored)
│   ├── ca/
│   ├── db/
│   └── user/
├── scripts/             # Python scripts
│   └── mtls.py         # mTLS data loading script
└── .venv/              # Python virtual environment (gitignored)
```

## Contributing

When modifying:

1. **Certificates**: Update both Makefile targets and .gitignore
2. **Cluster Config**: Keep docker-compose.yml in sync with Makefile NODE_IPS
3. **Python Script**: Update README with new parameters/features
4. **Dependencies**: Document in README and update make install

## License

This is a testing/development environment. Use at your own discretion.

## References

- [ScyllaDB Documentation](https://docs.scylladb.com/)
- [ScyllaDB SSL/TLS](https://docs.scylladb.com/stable/operating-scylla/security/client-node-encryption.html)
- [Python cassandra-driver](https://docs.datastax.com/en/developer/python-driver/)
- [uv Package Manager](https://github.com/astral-sh/uv)
