.PHONY: help venv install certs ca node-certs user-certs start stop restart status wait-cluster clean clean-certs run-mtls logs

# Configuration
PYTHON_VERSION ?= 3.12
VENV_DIR := .venv
UV := uv
CLUSTER_DIR := cluster
SCRIPTS_DIR := scripts
CONFIG_DIR := config
CA_DIR := $(CONFIG_DIR)/ca
DB_DIR := $(CONFIG_DIR)/db
USER_DIR := $(CONFIG_DIR)/user
NODES := scylla-1 scylla-2 scylla-3
NODE_IPS := 172.41.0.2 172.41.0.3 172.41.0.4

# Certificate parameters
CA_DAYS := 3650
CERT_DAYS := 365
COUNTRY := US
STATE := CA
CITY := SanFrancisco
ORG := ScyllaDB
OU := Testing

# mTLS script parameters
HOSTS ?= 172.41.0.2
KEYSPACE ?= mykeyspace
TABLE ?= myTable
ROW_COUNT ?= 100000
WORKERS ?= 0
DC ?= datacenter1

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

venv: ## Create Python virtual environment using uv
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "Creating virtual environment with Python $(PYTHON_VERSION)..."; \
		$(UV) venv $(VENV_DIR) --python $(PYTHON_VERSION); \
		echo "Virtual environment created at $(VENV_DIR)"; \
	else \
		echo "Virtual environment already exists at $(VENV_DIR)"; \
	fi

install: venv ## Install Python dependencies
	@echo "Installing dependencies..."
	@$(UV) pip install --python $(VENV_DIR) \
		cassandra-driver \
		faker
	@echo "Dependencies installed successfully"

ca: ## Create Certificate Authority (only if absent)
	@if [ ! -f "$(CA_DIR)/ca.crt" ]; then \
		echo "Creating Certificate Authority..."; \
		mkdir -p $(CA_DIR); \
		openssl genrsa -out $(CA_DIR)/ca.key 4096; \
		openssl req -new -x509 -days $(CA_DAYS) -key $(CA_DIR)/ca.key -out $(CA_DIR)/ca.crt \
			-subj "/C=$(COUNTRY)/ST=$(STATE)/L=$(CITY)/O=$(ORG)/OU=$(OU)/CN=ScyllaDB CA"; \
		echo "Certificate Authority created at $(CA_DIR)/"; \
	else \
		echo "Certificate Authority already exists at $(CA_DIR)/ca.crt"; \
	fi

node-certs: ca ## Create certificates for all nodes (only if absent)
	@for i in 1 2 3; do \
		node=scylla-$$i; \
		ip=$$(echo "$(NODE_IPS)" | cut -d' ' -f$$i); \
		if [ ! -f "$(CLUSTER_DIR)/$$node/db.crt" ]; then \
			echo "Creating certificate for $$node ($$ip)..."; \
			openssl genrsa -out $(CLUSTER_DIR)/$$node/db.key 2048; \
			openssl req -new -key $(CLUSTER_DIR)/$$node/db.key \
				-out $(CLUSTER_DIR)/$$node/db.csr \
				-subj "/C=$(COUNTRY)/ST=$(STATE)/L=$(CITY)/O=$(ORG)/OU=$(OU)/CN=$$node"; \
			echo "subjectAltName=DNS:$$node,DNS:$$node.local,IP:$$ip" > $(CLUSTER_DIR)/$$node/db.ext; \
			openssl x509 -req -in $(CLUSTER_DIR)/$$node/db.csr \
				-CA $(CA_DIR)/ca.crt -CAkey $(CA_DIR)/ca.key \
				-CAcreateserial -out $(CLUSTER_DIR)/$$node/db.crt \
				-days $(CERT_DAYS) -extfile $(CLUSTER_DIR)/$$node/db.ext; \
			rm -f $(CLUSTER_DIR)/$$node/db.csr $(CLUSTER_DIR)/$$node/db.ext; \
			cp $(CA_DIR)/ca.crt $(CLUSTER_DIR)/$$node/ca.crt; \
			echo "Certificate created for $$node"; \
		else \
			echo "Certificate already exists for $$node at $(CLUSTER_DIR)/$$node/db.crt"; \
		fi; \
	done

db-certs: ca ## Create database client certificates (only if absent)
	@if [ ! -f "$(DB_DIR)/db.crt" ]; then \
		echo "Creating database client certificates..."; \
		mkdir -p $(DB_DIR); \
		openssl genrsa -out $(DB_DIR)/db.key 2048; \
		openssl req -new -key $(DB_DIR)/db.key -out $(DB_DIR)/db.csr \
			-subj "/C=$(COUNTRY)/ST=$(STATE)/L=$(CITY)/O=$(ORG)/OU=$(OU)/CN=db-client"; \
		openssl x509 -req -in $(DB_DIR)/db.csr \
			-CA $(CA_DIR)/ca.crt -CAkey $(CA_DIR)/ca.key \
			-CAcreateserial -out $(DB_DIR)/db.crt -days $(CERT_DAYS); \
		rm -f $(DB_DIR)/db.csr; \
		cp $(CA_DIR)/ca.crt $(DB_DIR)/ca.crt; \
		echo "Database client certificates created at $(DB_DIR)/"; \
	else \
		echo "Database client certificates already exist at $(DB_DIR)/db.crt"; \
	fi

user-certs: ca ## Create user client certificate (only if absent)
	@if [ ! -f "$(USER_DIR)/user.crt" ]; then \
		echo "Creating user client certificate..."; \
		mkdir -p $(USER_DIR); \
		openssl genrsa -out $(USER_DIR)/user.key 2048; \
		openssl req -new -key $(USER_DIR)/user.key -out $(USER_DIR)/user.csr \
			-subj "/C=$(COUNTRY)/ST=$(STATE)/L=$(CITY)/O=$(ORG)/OU=$(OU)/CN=user-client"; \
		openssl x509 -req -in $(USER_DIR)/user.csr \
			-CA $(CA_DIR)/ca.crt -CAkey $(CA_DIR)/ca.key \
			-CAcreateserial -out $(USER_DIR)/user.crt -days $(CERT_DAYS); \
		rm -f $(USER_DIR)/user.csr; \
		cp $(CA_DIR)/ca.crt $(USER_DIR)/ca.crt; \
		echo "User client certificate created at $(USER_DIR)/"; \
	else \
		echo "User client certificate already exists at $(USER_DIR)/user.crt"; \
	fi

certs: ca node-certs db-certs user-certs ## Create all certificates (CA, nodes, db-client, and user)

start: node-certs ## Start the ScyllaDB cluster
	@echo "Starting ScyllaDB cluster..."
	@cd $(CLUSTER_DIR) && docker-compose up -d
	@echo "Cluster started. Use 'make status' to check health."

stop: ## Stop the ScyllaDB cluster
	@echo "Stopping ScyllaDB cluster..."
	@cd $(CLUSTER_DIR) && docker-compose down
	@echo "Cluster stopped."

restart: stop start ## Restart the ScyllaDB cluster

status: ## Check cluster status
	@cd $(CLUSTER_DIR) && docker-compose ps

logs: ## Show cluster logs
	@cd $(CLUSTER_DIR) && docker-compose logs -f

wait-cluster: ## Wait for all cluster nodes to be ready (UN state)
	@echo "Waiting for cluster to be ready (all 3 nodes in UN state)..."
	@MAX_ATTEMPTS=60; \
	ATTEMPT=0; \
	while [ $$ATTEMPT -lt $$MAX_ATTEMPTS ]; do \
		if docker exec cluster-scylla1-1 nodetool status 2>/dev/null | grep -c "UN" | grep -q "^3$$"; then \
			echo "Cluster is ready! All 3 nodes are UP and NORMAL."; \
			docker exec cluster-scylla1-1 nodetool status; \
			exit 0; \
		fi; \
		ATTEMPT=$$((ATTEMPT + 1)); \
		echo "Waiting for nodes to join cluster... (attempt $$ATTEMPT/$$MAX_ATTEMPTS)"; \
		sleep 2; \
	done; \
	echo "ERROR: Cluster did not become ready within $$((MAX_ATTEMPTS * 2)) seconds"; \
	docker exec cluster-scylla1-1 nodetool status 2>/dev/null || echo "Cannot reach scylla1"; \
	exit 1

run-mtls: install db-certs wait-cluster ## Run mTLS test script (use HOSTS=x.x.x.x to specify target)
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "Error: Virtual environment not found. Run 'make install' first."; \
		exit 1; \
	fi
	@echo "Running mTLS script against $(HOSTS)..."
	@$(VENV_DIR)/bin/python $(SCRIPTS_DIR)/mtls.py \
		--hosts $(HOSTS) \
		--keyspace $(KEYSPACE) \
		--table $(TABLE) \
		--row_count $(ROW_COUNT) \
		--workers $(WORKERS) \
		--dc $(DC)

clean: ## Clean up containers and volumes
	@echo "Cleaning up cluster..."
	@cd $(CLUSTER_DIR) && docker-compose down -v
	@echo "Cluster cleaned."

clean-certs: stop ## Remove all certificates (WARNING: destructive, stops cluster first)
	@echo "Removing all certificates..."
	@rm -rf $(CA_DIR) $(DB_DIR) $(USER_DIR)
	@for node in $(NODES); do \
		rm -f $(CLUSTER_DIR)/$$node/db.crt $(CLUSTER_DIR)/$$node/db.key $(CLUSTER_DIR)/$$node/ca.crt; \
	done
	@echo "Certificates removed. Run 'make start' to restart with new certificates."

clean-venv: ## Remove Python virtual environment
	@echo "Removing virtual environment..."
	@rm -rf $(VENV_DIR)
	@echo "Virtual environment removed."

clean-all: clean clean-certs clean-venv ## Clean everything (containers, certs, venv)
