#!/usr/bin/env bash

# ===========================================
# Step 1: Create Azure ML Environment
# ===========================================

set -e  # Exit on error

# Function to display usage
usage() {
    echo "Usage: $0 [config_file]"
    echo "  config_file: Path to configuration file (default: config.conf)"
    echo ""
    echo "This script creates an Azure ML environment using the Dockerfile in AML_env/"
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
        echo "❌ Not logged into Azure. Please run 'az login --tenant <directory-id, aka:tenant-id>' first."
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

# Function to copy AML environment to tmp folder
copy_aml_env_to_tmp() {
    echo "📁 Copying AML environment to tmp folder..."
    
    # Create tmp directory if it doesn't exist
    mkdir -p "${TMP_DIR}"
    
    # Remove existing AML_env in tmp if it exists
    if [[ -d "${TMP_DIR}/AML_env" ]]; then
        echo "🗑️  Removing existing AML_env from tmp folder..."
        rm -rf "${TMP_DIR}/AML_env"
    fi
    
    # Copy AML_env to tmp
    echo "📋 Copying ${AML_ENV_DIR} to ${TMP_DIR}/AML_env..."
    cp -r "${AML_ENV_DIR}" "${TMP_DIR}/AML_env"
    
    echo "✅ AML environment copied to ${TMP_DIR}/AML_env"
}

# Function to create environment YAML
create_environment_yaml() {
    echo "📝 Creating environment YAML file..."
    
    mkdir -p "${TMP_DIR}"
    
    cat > "${TMP_DIR}/environment.yml" <<EOF
\$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: ${AZ_ENVIRONMENT_NAME}
version: ${AZ_ENVIRONMENT_VERSION}
description: ${AZ_ENVIRONMENT_DESCRIPTION}
build:
  path: ./AML_env/
EOF
    
    echo "✅ Environment YAML created at ${TMP_DIR}/environment.yml"
}

# Main execution
main() {
    echo "🚀 Starting Azure ML Environment Creation"
    echo "========================================"
    
    # Parse arguments
    CONFIG_FILE="${1:-config.conf}"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "❌ Config file '${CONFIG_FILE}' not found."
        usage
    fi
    
    # Source the config file
    echo "📖 Loading configuration from ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    
    # Check if using public registry environment
    if [[ "${AZ_ENVIRONMENT_NAME}" == azureml://* ]]; then
        echo "ℹ️  Using public registry environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
        echo "✅ Skipping environment creation - public registry environment will be used directly"
        echo ""
        echo "🎉 Environment Setup Complete!"
        echo "   Environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
        echo "   Next step: Run './scripts/02-create-endpoint-deployment.sh' to create endpoint and deployment"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Set Azure context
    echo "🔧 Setting Azure context..."
    az account set --subscription "${AZ_SUBSCRIPTION_ID}"
    az configure --defaults workspace="${AZ_ML_WORKSPACE}" group="${AZ_RESOURCE_GROUP}"
    echo "✅ Azure context set (Subscription: ${AZ_SUBSCRIPTION_ID}, Workspace: ${AZ_ML_WORKSPACE})"
    
    # Check if AML_env directory exists
    if [[ ! -d "${AML_ENV_DIR}" ]]; then
        echo "❌ AML environment directory '${AML_ENV_DIR}' not found."
        exit 1
    fi
    
    if [[ ! -f "${AML_ENV_DIR}/Dockerfile" ]]; then
        echo "❌ Dockerfile not found in '${AML_ENV_DIR}'"
        exit 1
    fi
    
    echo "✅ Found AML environment directory and Dockerfile"
    
    # Copy AML environment to tmp folder
    copy_aml_env_to_tmp
    
    # Create environment YAML
    create_environment_yaml
    
    # Check if environment already exists
    echo "🔍 Checking if environment already exists..."
    if az ml environment show --name "${AZ_ENVIRONMENT_NAME}" --version "${AZ_ENVIRONMENT_VERSION}" &> /dev/null; then
        echo "⚠️  Environment ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION} already exists"
        echo "ℹ️  Skipping environment creation"
        exit 0
    
    fi
    
    # Create the environment
    echo "🏗️  Creating Azure ML environment..."
    echo "   Name: ${AZ_ENVIRONMENT_NAME}"
    echo "   Version: ${AZ_ENVIRONMENT_VERSION}"
    echo "   Build Path: ${TMP_DIR}/AML_env"
    echo "   This may take 10-20 minutes for container build..."
    
    
    if az ml environment create -f "${TMP_DIR}/environment.yml"; then
        echo "✅ Environment created successfully!"
        echo ""
        echo "🎉 Azure ML Environment Creation Complete!"
        echo "   Environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
        echo "   Next step: Run './scripts/02-create-endpoint-deployment.sh' to create endpoint and deployment"
    else
        echo "❌ Failed to create environment"
        exit 1
    fi
}

# Show help if requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# Run main function
main "$@"
