#!/usr/bin/env bash

# ===========================================
# Step 2: Create Azure ML Endpoint and Deployment
# ===========================================

set -e  # Exit on error

# Function to display usage
usage() {
    echo "Usage: $0 [config_file] [OPTIONS]"
    echo "  config_file: Path to configuration file (default: config.conf)"
    echo ""
    echo "OPTIONS:"
    echo "  --force    Automatically update existing deployments without prompting"
    echo ""
    echo "This script creates an Azure ML online endpoint and deployment"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        echo "❌ Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        echo "❌ Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if environment exists (skip check if it's a public registry reference)
    if [[ "${AZ_ENVIRONMENT_NAME}" != azureml://* ]]; then
        if az ml environment show --name "${AZ_ENVIRONMENT_NAME}" --version "${AZ_ENVIRONMENT_VERSION}" &> /dev/null; then
            echo "ℹ️  Using existing environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
        else
            echo "❌ Environment ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION} not found."
            echo "   Please run './scripts/01-create-environment.sh' first."
            exit 1
        fi
    else
        echo "ℹ️  Using public registry environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
    fi
    
    echo "✅ Prerequisites check passed"
}

# Function to create endpoint YAML
create_endpoint_yaml() {
    echo "📝 Creating endpoint YAML file..."
    
    mkdir -p "${TMP_DIR}"
    
    cat > "${TMP_DIR}/endpoint.yml" <<EOF
\$schema: https://azuremlsdk2.blob.core.windows.net/latest/managedOnlineEndpoint.schema.json
name: ${AZ_ENDPOINT_NAME}
description: "vLLM endpoint for ${AZ_MODEL_NAME}"
auth_mode: key
tags:
  model: ${AZ_MODEL_NAME}
  framework: vllm
  created_by: automated_script
EOF
    
    echo "✅ Endpoint YAML created at ${TMP_DIR}/endpoint.yml"
}

# Function to create deployment YAML
create_deployment_yaml() {
    echo "📝 Creating deployment YAML file..."
    
    cat > "${TMP_DIR}/deployment.yml" <<EOF
\$schema: https://azuremlschemas.azureedge.net/latest/managedOnlineDeployment.schema.json
name: ${AZ_DEPLOYMENT_NAME}
description: "vLLM deployment for ${AZ_MODEL_NAME}"
endpoint_name: ${AZ_ENDPOINT_NAME}
model: ${AZ_MODEL_ID}
environment: azureml:${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}
instance_type: ${AZ_INSTANCE_TYPE}
instance_count: ${AZ_INSTANCE_COUNT}
request_settings:
  request_timeout_ms: ${REQUEST_TIMEOUT_MS}
  max_concurrent_requests_per_instance: ${MAX_CONCURRENT_REQUESTS}
  max_queue_wait_ms: ${MAX_QUEUE_WAIT_MS}
environment_variables:
  # Core vLLM settings
  GPU_MEMORY_UTILIZATION: "${GPU_MEMORY_UTILIZATION}"
  VLLM_TENSOR_PARALLEL_SIZE: "${VLLM_TENSOR_PARALLEL_SIZE}"
  VLLM_ATTENTION_BACKEND: "${VLLM_ATTENTION_BACKEND}"
  VLLM_SWAP_SPACE: "${VLLM_SWAP_SPACE}"
  VLLM_FLASH_ATTN_VERSION: "3"
  VLLM_USE_V1: "1"

  # Task type for Azure ML
  TASK_TYPE: "chat-completion"
  
liveness_probe:
  initial_delay: ${INITIAL_DELAY}
  timeout: ${PROBE_TIMEOUT}
  period: ${PROBE_PERIOD}
  failure_threshold: ${FAILURE_THRESHOLD}
readiness_probe:
  initial_delay: ${INITIAL_DELAY}
  timeout: ${PROBE_TIMEOUT}
  period: ${PROBE_PERIOD}
  failure_threshold: ${FAILURE_THRESHOLD}
tags:
  model: ${AZ_MODEL_NAME}
  instance_type: ${AZ_INSTANCE_TYPE}
  created_by: automated_script
EOF
    
    echo "✅ Deployment YAML created at ${TMP_DIR}/deployment.yml"
}

# Function to create endpoint
create_endpoint() {
    echo "🔍 Checking if endpoint exists..."
    
    if az ml online-endpoint show --name "${AZ_ENDPOINT_NAME}" &> /dev/null; then
        echo "⚠️  Endpoint ${AZ_ENDPOINT_NAME} already exists"
        read -p "Do you want to continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "ℹ️  Stopping execution"
            exit 0
        fi
    else
        echo "🏗️  Creating endpoint..."
        
        
        if az ml online-endpoint create -f "${TMP_DIR}/endpoint.yml"; then
            echo "✅ Endpoint created successfully!"
        else
            echo "❌ Failed to create endpoint"
            exit 1
        fi
    fi
}

# Function to set traffic to deployment
set_deployment_traffic() {
    echo "🚦 Setting 100% traffic to deployment ${AZ_DEPLOYMENT_NAME}..."
    
    if az ml online-endpoint update --name "${AZ_ENDPOINT_NAME}" --traffic "${AZ_DEPLOYMENT_NAME}=100"; then
        echo "✅ Traffic allocation set successfully!"
        echo "   ${AZ_DEPLOYMENT_NAME}: 100%"
        return 0
    else
        echo "❌ Failed to set traffic allocation"
        return 1
    fi
}

# Function to wait for deployment to be ready
wait_for_deployment_ready() {
    local endpoint_name="$1"
    local deployment_name="$2"
    local max_attempts=120  # 2 hours (120 * 60 seconds)
    local attempt=1
    
    echo "⏳ Waiting for deployment ${deployment_name} to be ready..."
    echo "   This may take 10-30 minutes depending on the model size and instance type"
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "🔍 Checking deployment status (attempt ${attempt}/${max_attempts})..."
        
        # Get deployment status
        local status
        status=$(az ml online-deployment show --name "${deployment_name}" --endpoint-name "${endpoint_name}" --query "provisioning_state" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   Current status: ${status}"
        
        case "${status}" in
            "Succeeded")
                echo "✅ Deployment ${deployment_name} is ready!"
                return 0
                ;;
            "Failed")
                echo "❌ Deployment ${deployment_name} failed!"
                echo "   Check the deployment logs for more details:"
                echo "   az ml online-deployment get-logs --name ${deployment_name} --endpoint-name ${endpoint_name}"
                return 1
                ;;
            "Canceled"|"Cancelled")
                echo "❌ Deployment ${deployment_name} was canceled!"
                return 1
                ;;
            "Creating"|"Updating"|"InProgress|NotFound")
                echo "   Deployment is still in progress..."
                ;;
            *)
                echo "   Unknown status: ${status}"
                ;;
        esac
        
        if [[ $attempt -eq $max_attempts ]]; then
            echo "❌ Timeout waiting for deployment to be ready after 2 hours"
            echo "   Current status: ${status}"
            echo "   You can check the status manually with:"
            echo "   az ml online-deployment show --name ${deployment_name} --endpoint-name ${endpoint_name}"
            return 1
        fi
        
        echo "   Waiting 60 seconds before next check..."
        sleep 60
        ((attempt++))
    done
}

# Function to create deployment
create_deployment() {
    echo "🔍 Checking if deployment exists..."
    
    if az ml online-deployment show --name "${AZ_DEPLOYMENT_NAME}" --endpoint-name "${AZ_ENDPOINT_NAME}" &> /dev/null; then
        echo "⚠️  Deployment ${AZ_DEPLOYMENT_NAME} already exists"
        
        local should_update=false
        if [[ "${FORCE}" == "true" ]]; then
            echo "🔄 Force mode enabled - will update existing deployment"
            should_update=true
        else
            read -p "Do you want to update it? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                should_update=true
            fi
        fi
        
        if [[ "$should_update" == "true" ]]; then
            echo "🔄 Updating existing deployment..."
            echo "   Starting deployment update (asynchronous)..."
            
            
            if az ml online-deployment update -f "${TMP_DIR}/deployment.yml" --no-wait; then
                echo "✅ Deployment update started successfully!"
                echo "   Waiting for deployment to be ready..."
                
                # Wait for deployment to be ready
                if wait_for_deployment_ready "${AZ_ENDPOINT_NAME}" "${AZ_DEPLOYMENT_NAME}"; then
                    echo "✅ Deployment update completed successfully!"
                    # Set traffic to the updated deployment
                    set_deployment_traffic
                    return 0
                else
                    echo "❌ Deployment update failed or timed out"
                    return 1
                fi
            else
                echo "❌ Failed to start deployment update"
                return 1
            fi
        else
            echo "ℹ️  Skipping deployment creation/update"
            echo "💡 Note: Deployment ${AZ_DEPLOYMENT_NAME} already exists and was not modified"
            return 0
        fi
    else
        echo "🏗️  Creating new deployment..."
        echo "   Starting deployment creation (asynchronous)..."
       
        
        if az ml online-deployment create -f "${TMP_DIR}/deployment.yml" --all-traffic --no-wait; then
            echo "✅ Deployment creation started successfully!"
            echo "   Waiting for deployment to be ready..."
            
            # Wait for deployment to be ready
            if wait_for_deployment_ready "${AZ_ENDPOINT_NAME}" "${AZ_DEPLOYMENT_NAME}"; then
                echo "✅ Deployment creation completed successfully!"
                # Explicitly set traffic to ensure 100% allocation
                set_deployment_traffic
                return 0
            else
                echo "❌ Deployment creation failed or timed out"
                return 1
            fi
        else
            echo "❌ Failed to start deployment creation"
            return 1
        fi
    fi
}

# Function to show endpoint information
show_endpoint_info() {
    echo ""
    echo "📋 Endpoint Information:"
    echo "========================"
    
    # Get endpoint details
    ENDPOINT_URI=$(az ml online-endpoint show --name "${AZ_ENDPOINT_NAME}" --query "scoring_uri" -o tsv 2>/dev/null || echo "Not available")
    
    echo "Endpoint Name: ${AZ_ENDPOINT_NAME}"
    echo "Deployment Name: ${AZ_DEPLOYMENT_NAME}"
    echo "Scoring URI: ${ENDPOINT_URI}"
    echo ""
    echo "To get the endpoint key, run:"
    echo "az ml online-endpoint get-credentials --name ${AZ_ENDPOINT_NAME}"
}

# Main execution
main() {
    echo "🚀 Starting Azure ML Endpoint and Deployment Creation"
    echo "===================================================="
    
    # Parse arguments
    CONFIG_FILE="config.conf"
    FORCE="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                echo "❌ Unknown option: $1"
                usage
                ;;
            *)
                CONFIG_FILE="$1"
                shift
                ;;
        esac
    done
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "❌ Config file '${CONFIG_FILE}' not found."
        usage
    fi
    
    # Source the config file
    echo "📖 Loading configuration from ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    
    # Check prerequisites
    check_prerequisites
    
    # Set Azure context
    echo "🔧 Setting Azure context..."
    az account set --subscription "${AZ_SUBSCRIPTION_ID}"
    az configure --defaults workspace="${AZ_ML_WORKSPACE}" group="${AZ_RESOURCE_GROUP}"
    echo "✅ Azure context set"
    
    # Create YAML files
    create_endpoint_yaml
    create_deployment_yaml
    
    # Create endpoint
    create_endpoint
    
    # Create deployment
    if create_deployment; then
        echo ""
        echo "🎉 Endpoint and Deployment Creation Complete!"
        show_endpoint_info
    else
        echo "❌ Deployment creation failed"
        exit 1
    fi
}

# Show help if requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# Run main function
main "$@"
