#!/usr/bin/env bash

# ===========================================
# Cleanup: Delete Azure ML Resources
# ===========================================

set -e  # Exit on error

# Function to display usage
usage() {
    echo "Usage: $0 [config_file] [OPTIONS]"
    echo "  config_file: Path to configuration file (default: config.conf)"
    echo ""
    echo "OPTIONS:"
    echo "  --deployment-only    Delete only the deployment, keep endpoint"
    echo "  --endpoint-only      Delete only the endpoint (this will delete deployment too)"
    echo "  --environment-only   Delete only the environment"
    echo "  --all               Delete all resources (default)"
    echo "  --force             Skip confirmation prompts"
    echo ""
    echo "This script cleans up Azure ML resources created by the deployment scripts"
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
    
    echo "✅ Prerequisites check passed"
}

# Function to confirm action
confirm_action() {
    local action="$1"
    
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo "⚠️  WARNING: This will ${action}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "ℹ️  Operation cancelled"
        return 1
    fi
    return 0
}

# Function to delete deployment
delete_deployment() {
    echo "🔍 Checking if deployment exists..."
    
    if az ml online-deployment show --name "${AZ_DEPLOYMENT_NAME}" --endpoint-name "${AZ_ENDPOINT_NAME}" &> /dev/null; then
        if confirm_action "delete deployment ${AZ_DEPLOYMENT_NAME}"; then
            echo "🗑️  Deleting deployment..."
            if az ml online-deployment delete --name "${AZ_DEPLOYMENT_NAME}" --endpoint-name "${AZ_ENDPOINT_NAME}" --yes; then
                echo "✅ Deployment deleted successfully!"
            else
                echo "❌ Failed to delete deployment"
                return 1
            fi
        else
            return 1
        fi
    else
        echo "ℹ️  Deployment ${AZ_DEPLOYMENT_NAME} not found or already deleted"
    fi
}

# Function to delete endpoint
delete_endpoint() {
    echo "🔍 Checking if endpoint exists..."
    
    if az ml online-endpoint show --name "${AZ_ENDPOINT_NAME}" &> /dev/null; then
        if confirm_action "delete endpoint ${AZ_ENDPOINT_NAME} (this will also delete all deployments)"; then
            echo "🗑️  Deleting endpoint..."
            if az ml online-endpoint delete --name "${AZ_ENDPOINT_NAME}" --yes; then
                echo "✅ Endpoint deleted successfully!"
            else
                echo "❌ Failed to delete endpoint"
                return 1
            fi
        else
            return 1
        fi
    else
        echo "ℹ️  Endpoint ${AZ_ENDPOINT_NAME} not found or already deleted"
    fi
}

# Function to delete environment
delete_environment() {
    echo "🔍 Checking if environment exists..."
    
    if az ml environment show --name "${AZ_ENVIRONMENT_NAME}" --version "${AZ_ENVIRONMENT_VERSION}" &> /dev/null; then
        if confirm_action "delete environment ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"; then
            echo "🗑️  Deleting environment..."
            if az ml environment delete --name "${AZ_ENVIRONMENT_NAME}" --version "${AZ_ENVIRONMENT_VERSION}" --yes; then
                echo "✅ Environment deleted successfully!"
            else
                echo "❌ Failed to delete environment"
                return 1
            fi
        else
            return 1
        fi
    else
        echo "ℹ️  Environment ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION} not found or already deleted"
    fi
}

# Function to clean temp files
clean_temp_files() {
    echo "🧹 Cleaning temporary files..."
    
    if [[ -d "${TMP_DIR}" ]]; then
        if confirm_action "delete temporary files in ${TMP_DIR}"; then
            rm -rf "${TMP_DIR}"/*
            echo "✅ Temporary files cleaned"
        fi
    else
        echo "ℹ️  No temporary files to clean"
    fi
}

# Main execution
main() {
    echo "🧹 Starting Azure ML Resources Cleanup"
    echo "======================================"
    
    # Parse arguments
    CONFIG_FILE=""
    MODE="all"
    FORCE="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --deployment-only)
                MODE="deployment"
                shift
                ;;
            --endpoint-only)
                MODE="endpoint"
                shift
                ;;
            --environment-only)
                MODE="environment"
                shift
                ;;
            --all)
                MODE="all"
                shift
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [[ -z "${CONFIG_FILE}" ]]; then
                    CONFIG_FILE="$1"
                else
                    echo "❌ Unknown option: $1"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    # Set default config file if not provided
    CONFIG_FILE="${CONFIG_FILE:-config.conf}"
    
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
    
    echo "🎯 Cleanup mode: ${MODE}"
    echo ""
    
    # Execute cleanup based on mode
    case "${MODE}" in
        "deployment")
            delete_deployment
            ;;
        "endpoint")
            delete_endpoint
            ;;
        "environment")
            delete_environment
            ;;
        "all")
            # Delete in reverse order of creation
            delete_deployment || true
            delete_endpoint || true
            delete_environment || true
            clean_temp_files
            ;;
        *)
            echo "❌ Unknown mode: ${MODE}"
            usage
            ;;
    esac
    
    echo ""
    echo "🎉 Cleanup Complete!"
}

# Run main function
main "$@"
