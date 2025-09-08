#!/usr/bin/env bash

# ===========================================
# Main Deployment Script
# ===========================================

set -e  # Exit on error

# Function to display usage
usage() {
    echo "Azure ML vLLM Deployment Orchestrator"
    echo "===================================="
    echo ""
    echo "Usage: $0 [OPTIONS] [config_file]"
    echo "  config_file: Path to configuration file (default: config.conf)"
    echo ""
    echo "OPTIONS:"
    echo "  --env-only          Create only the environment"
    echo "  --endpoint-only     Create only endpoint and deployment (requires existing environment)"
    echo "  --cleanup           Clean up all resources"
    echo "  --force             Skip confirmation prompts"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                           # Full deployment with default config"
    echo "  $0 custom.conf               # Full deployment with custom config"
    echo "  $0 --env-only                # Create only environment"
    echo "  $0 --cleanup --force         # Clean up all resources without confirmation"
    echo ""
    echo "STEP-BY-STEP USAGE:"
    echo "  1. $0 --env-only             # Create environment first"
    echo "  2. $0 --endpoint-only        # Create endpoint and deployment"
    echo ""
    exit 1
}

# Function to check if scripts exist
check_scripts() {
    local scripts_dir="./scripts"
    local required_scripts=(
        "01-create-environment.sh"
        "02-create-endpoint-deployment.sh"
        "cleanup.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "${scripts_dir}/${script}" ]]; then
            echo "❌ Required script not found: ${scripts_dir}/${script}"
            exit 1
        fi
        
        if [[ ! -x "${scripts_dir}/${script}" ]]; then
            echo "🔧 Making script executable: ${scripts_dir}/${script}"
            chmod +x "${scripts_dir}/${script}"
        fi
    done
    
    echo "✅ All required scripts found and executable"
}


# Function to display configuration summary
show_config_summary() {
    echo ""
    echo "📋 Deployment Configuration Summary:"
    echo "===================================="
    echo "Subscription ID: ${AZ_SUBSCRIPTION_ID}"
    echo "Resource Group: ${AZ_RESOURCE_GROUP}"
    echo "ML Workspace: ${AZ_ML_WORKSPACE}"
    echo "Environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
    echo "Endpoint: ${AZ_ENDPOINT_NAME}"
    echo "Deployment: ${AZ_DEPLOYMENT_NAME}"
    echo "Instance Type: ${AZ_INSTANCE_TYPE}"
    echo "Instance Count: ${AZ_INSTANCE_COUNT}"
    echo "Model: ${AZ_MODEL_NAME}"
    echo ""
}

# Function to run environment creation
run_environment_creation() {
    echo "🎯 Step 1: Creating Azure ML Environment"
    echo "========================================"
    ./scripts/01-create-environment.sh "${CONFIG_FILE}"
    echo ""
}

# Function to run endpoint and deployment creation
run_endpoint_deployment_creation() {
    echo "🎯 Step 2: Creating Endpoint and Deployment"
    echo "=========================================="
    
    # Check if using public registry environment and skip confirmation
    if [[ "${AZ_ENVIRONMENT_NAME}" == azureml://* ]]; then
        echo "ℹ️  Using public registry environment - proceeding with endpoint creation"
    else
        # Ask user to confirm environment is ready for custom environments
        echo ""
        echo "⚠️  IMPORTANT: Environment Status Confirmation Required"
        echo "====================================================="
        echo ""
        echo "Before creating the endpoint, please ensure that your environment:"
        echo "   Environment: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
        echo ""
        echo "✅ Has completed building successfully (Status: 'Succeeded')"
        echo "✅ Is visible in your Azure ML workspace"
        echo ""
        echo "💡 You can check the environment status in the Azure ML Studio:"
        echo "   - Go to your workspace -> Environments"
        echo "   - Look for '${AZ_ENVIRONMENT_NAME}' version '${AZ_ENVIRONMENT_VERSION}'"
        echo "   - Verify the status shows 'Succeeded'"
        echo ""
        echo "⏰ Environment building can take up to 25 minutes to complete."
        echo "   Creating the endpoint before the environment is ready may cause"
        echo "   timeout issues during the deployment process."
        echo ""
        
        read -p "Is your environment ready and showing 'Succeeded' status? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "ℹ️  Deployment cancelled. Please wait for the environment to complete building."
            echo "   You can run this script again once the environment status is 'Succeeded'."
            exit 0
        fi
        
        echo "✅ Proceeding with endpoint creation..."
        echo ""
    fi
    
    local force_flag=""
    if [[ "${FORCE}" == "true" ]]; then
        force_flag="--force"
    fi
    
    ./scripts/02-create-endpoint-deployment.sh ${force_flag} "${CONFIG_FILE}"
    echo ""
}


# Function to run cleanup
run_cleanup() {
    echo "🎯 Cleanup: Removing Resources"
    echo "============================="
    if [[ "${FORCE}" == "true" ]]; then
        ./scripts/cleanup.sh "${CONFIG_FILE}" --all --force
    else
        ./scripts/cleanup.sh "${CONFIG_FILE}" --all
    fi
    echo ""
}

# Function to confirm full deployment
confirm_full_deployment() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo "⚠️  This will create:"
    echo "   - Azure ML Environment (may take 5-10 minutes)"
    echo "   - Azure ML Endpoint"
    echo "   - Azure ML Deployment (may take 10-15 minutes)"
    echo ""
    echo "💰 Note: This will incur Azure costs based on your instance type and usage."
    echo ""
    read -p "Do you want to continue with the full deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "ℹ️  Deployment cancelled"
        return 1
    fi
    return 0
}

# Main execution
main() {
    echo "🚀 Azure ML vLLM Deployment Orchestrator"
    echo "========================================"
    echo ""
    
    # Parse arguments
    CONFIG_FILE=""
    MODE="full"
    FORCE="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env-only)
                MODE="env"
                shift
                ;;
            --endpoint-only)
                MODE="endpoint"
                shift
                ;;
            --test-only)
                MODE="test"
                shift
                ;;
            --cleanup)
                MODE="cleanup"
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
        echo "   Please create a config file or use the default 'config.conf'"
        exit 1
    fi
    
    # Source the config file
    echo "📖 Loading configuration from ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    
    # Check required scripts
    check_scripts
    
    # Show configuration summary
    show_config_summary
    
    # Execute based on mode
    case "${MODE}" in
        "env")
            run_environment_creation
            echo "🎉 Environment creation complete!"
            echo "   Next step: Run '$0 --endpoint-only ${CONFIG_FILE}' to create endpoint and deployment"
            ;;
        "endpoint")
            run_endpoint_deployment_creation
            echo "🎉 Endpoint and deployment creation complete!"
            ;;
        "cleanup")
            run_cleanup
            echo "🎉 Cleanup complete!"
            ;;
        "full")
            if confirm_full_deployment; then
                echo "🚀 Starting full deployment..."
                echo ""
                
                # Run all steps
                run_environment_creation
                
                run_endpoint_deployment_creation
                
                
                echo "🎉 Full Deployment Complete!"
                echo ""
                echo "📋 Summary:"
                echo "==========="
                echo "✅ Environment created: ${AZ_ENVIRONMENT_NAME}:${AZ_ENVIRONMENT_VERSION}"
                echo "✅ Endpoint created: ${AZ_ENDPOINT_NAME}"
                echo "✅ Deployment created: ${AZ_DEPLOYMENT_NAME}"
                echo "✅ Endpoint tested successfully"
                echo ""
                echo "🔧 Management Commands:"
                echo "======================"
                echo "View endpoint: az ml online-endpoint show --name ${AZ_ENDPOINT_NAME}"
                echo "Get credentials: az ml online-endpoint get-credentials --name ${AZ_ENDPOINT_NAME}"
                echo "View logs: az ml online-deployment get-logs --name ${AZ_DEPLOYMENT_NAME} --endpoint-name ${AZ_ENDPOINT_NAME}"
                echo "Test again: $0 --test-only ${CONFIG_FILE}"
                echo "Cleanup: $0 --cleanup ${CONFIG_FILE}"
            fi
            ;;
        *)
            echo "❌ Unknown mode: ${MODE}"
            usage
            ;;
    esac
}

# Show help if no arguments or help requested
if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# Run main function
main "$@"
