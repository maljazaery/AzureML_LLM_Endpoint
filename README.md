# Shell Script to deploy LLM AML Online Enpoints

This repository contains automated shell scripts for deploying LLM models as Azure Machine Learning Online Endpoint with configurable parameters and easy-to-use execution flow.

## Included Examples

- **GPT-OSS Docker and Environment:** See `./AML_env/gpt_oss/` for a sample Dockerfile and environment setup.
- **GPT-OSS-20B on NV-A10:** Example configuration available at `./configs/config_a10.conf`.
- **GPT-OSS-20B on NC-H100:** Example configuration available at `./configs/config_h100.conf`.

## 🚀 Quick Start

### Prerequisites

1. **Azure CLI** installed and configured
2. **Azure ML workspace** already created
3. Proper **Azure permissions** for creating ML resources

```bash
# Install Azure CLI (if not already installed)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login
```

### Configuration

1. Create `config.conf` to match your Azure environment (check ./configs for examples):

```bash
# Azure subscription & workspace settings
AZ_SUBSCRIPTION_ID="your-subscription-id"
AZ_RESOURCE_GROUP="your-resource-group"
AZ_ML_WORKSPACE="your-workspace-name"

# Endpoint and deployment settings
AZ_ENDPOINT_NAME="gptoss-endpoint-h100"
AZ_INSTANCE_TYPE="Standard_NC40ads_H100_v5"
# ... other settings
```

### Deployment Options

#### Option 1: Full Automated Deployment

```bash
# Make the main script executable
chmod +x deploy-main.sh

# Run full deployment
./deploy-main.sh   custom.conf
```

#### Option 2: Step-by-Step Deployment

```bash
# Step 1: Create environment only
./deploy-main.sh --env-only  custom.conf

# Step 2: Create endpoint and deployment
./deploy-main.sh --endpoint-only  custom.conf

```

### Manual Testing

#### Bash
```bash
# Get endpoint credentials
az ml online-endpoint get-credentials --name your-endpoint-name

# Test with curl
curl -X POST "https://<your-endpoint>.<region>.inference.ml.azure.com/chat/completions" \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

#### OpenAI SDK
```bash
from openai import OpenAI
 
client = OpenAI(
    base_url= "https://your-endpoint.region.inference.ml.azure.com",
    api_key="your-key"
)
 
result = client.chat.completions.create(
    model="openai/gpt-oss-20b",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello!"}
    ]
)
 
print(result.choices[0].message)
```

## 📊 Monitoring and Management

### View Resources

```bash
# List endpoints
az ml online-endpoint list

# Show endpoint details
az ml online-endpoint show --name your-endpoint-name

# List deployments
az ml online-deployment list --endpoint-name your-endpoint-name

# View environment
az ml environment show --name your-environment-name --version 1
```

### Logs and Debugging

```bash
# Get deployment logs
az ml online-deployment get-logs --name current --endpoint-name your-endpoint-name

# Monitor in real-time
az ml online-deployment get-logs --name current --endpoint-name your-endpoint-name --lines 100 --follow
```
