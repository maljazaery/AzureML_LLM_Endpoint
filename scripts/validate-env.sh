#!/bin/bash

# ===========================================
# Environment Variables Validation Script
# ===========================================

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the configuration
source "${PROJECT_ROOT}/config.conf"

echo "🔍 Environment Variables Validation"
echo "====================================="

# Function to display environment variable with validation
show_env_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    local is_required="$2"
    
    printf "%-30s: " "$var_name"
    
    if [[ -n "$var_value" ]]; then
        echo "✅ $var_value"
    elif [[ "$is_required" == "required" ]]; then
        echo "❌ MISSING (Required)"
        return 1
    else
        echo "⚠️  NOT SET (Optional)"
    fi
    return 0
}

echo ""
echo "📋 Azure Configuration:"
echo "----------------------"
show_env_var "AZ_SUBSCRIPTION_ID" "required"
show_env_var "AZ_RESOURCE_GROUP" "required"
show_env_var "AZ_ML_WORKSPACE" "required"
show_env_var "AZ_ENVIRONMENT_NAME" "required"
show_env_var "AZ_ENDPOINT_NAME" "required"
show_env_var "AZ_DEPLOYMENT_NAME" "required"

echo ""
echo "🤖 Model Configuration:"
echo "-----------------------"
show_env_var "MODEL_ID" "required"
show_env_var "MODEL_REVISION" "optional"
show_env_var "MODEL_CACHE_DIR" "optional"
show_env_var "VLLM_SERVED_MODEL_NAME" "optional"


echo ""
echo "🔧 Advanced Settings:"
echo "---------------------"
show_env_var "VLLM_TOKENIZER_MODE" "optional"
show_env_var "VLLM_TRUST_REMOTE_CODE" "optional"
show_env_var "VLLM_LOG_LEVEL" "optional"
show_env_var "VLLM_WORKER_USE_RAY" "optional"
show_env_var "VLLM_ENGINE_USE_RAY" "optional"

echo ""
echo "🔗 Custom Variables:"
echo "--------------------"
show_env_var "CUSTOM_ENV_VAR_1" "optional"
show_env_var "CUSTOM_ENV_VAR_2" "optional"

echo ""
echo "💻 Compute Resources:"
echo "--------------------"
show_env_var "AZ_INSTANCE_TYPE" "required"
show_env_var "AZ_INSTANCE_COUNT" "required"
show_env_var "REQUEST_TIMEOUT_MS" "optional"
show_env_var "MAX_CONCURRENT_REQUESTS" "optional"

echo ""
echo "📁 File Paths:"
echo "--------------"
show_env_var "TMP_DIR" "required"
show_env_var "AML_ENV_DIR" "required"

echo ""
echo "======================================"

# Check if all required variables are set
missing_vars=0
for var in AZ_SUBSCRIPTION_ID AZ_RESOURCE_GROUP AZ_ML_WORKSPACE AZ_ENVIRONMENT_NAME AZ_ENDPOINT_NAME AZ_DEPLOYMENT_NAME MODEL_ID AZ_INSTANCE_TYPE AZ_INSTANCE_COUNT TMP_DIR AML_ENV_DIR; do
    if [[ -z "${!var}" ]]; then
        ((missing_vars++))
    fi
done

if [[ $missing_vars -eq 0 ]]; then
    echo "✅ All required environment variables are set!"
    echo ""
    echo "💡 To update any variables, edit: ${PROJECT_ROOT}/config.conf"
    exit 0
else
    echo "❌ $missing_vars required environment variable(s) are missing!"
    echo ""
    echo "💡 Please update: ${PROJECT_ROOT}/config.conf"
    exit 1
fi
