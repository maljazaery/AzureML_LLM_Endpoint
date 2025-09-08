#!/usr/bin/env bash

# ===========================================
# Update Traffic Allocation
# ===========================================

set -e  # Exit on error

# Function to display usage
usage() {
    echo "Usage: $0 [config_file] [deployment_name] [traffic_percentage]"
    echo "  config_file: Path to configuration file (default: config.conf)"
    echo "  deployment_name: Name of deployment to set traffic to (default: from config)"
    echo "  traffic_percentage: Percentage of traffic (default: 100)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                                    # Set 100% traffic to default deployment"
    echo "  $0 config.conf my-deployment 100     # Set 100% traffic to my-deployment"
    echo "  $0 config.conf my-deployment 50      # Set 50% traffic to my-deployment"
    echo ""
    echo "This script updates traffic allocation for Azure ML endpoint deployments"
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


# Function to show current traffic allocation
show_current_traffic() {
    echo "📊 Current traffic allocation for endpoint ${AZ_ENDPOINT_NAME}:"
    echo "================================================================"
    
    if az ml online-endpoint show --name "${AZ_ENDPOINT_NAME}" --query "traffic" -o table; then
        echo ""
    else
        echo "❌ Failed to retrieve current traffic allocation"
        return 1
    fi
}

# Function to set traffic allocation
set_traffic_allocation() {
    local deployment_name="$1"
    local traffic_percentage="$2"
    
    echo "🚦 Setting ${traffic_percentage}% traffic to deployment ${deployment_name}..."
    
    # Build traffic allocation string
    local traffic_allocation="${deployment_name}=${traffic_percentage}"
    
    # If not 100%, we might need to handle other deployments
    if [[ "${traffic_percentage}" != "100" ]]; then
        echo "⚠️  Warning: Setting traffic to ${traffic_percentage}% may require manual adjustment of other deployments"
        echo "   Make sure the total traffic allocation adds up to 100%"
    fi
    
    if az ml online-endpoint update --name "${AZ_ENDPOINT_NAME}" --traffic "${traffic_allocation}"; then
        echo "✅ Traffic allocation updated successfully!"
        echo ""
        show_current_traffic
        return 0
    else
        echo "❌ Failed to update traffic allocation"
        return 1
    fi
}

# Main execution
main() {
    echo "🚦 Azure ML Traffic Allocation Manager"
    echo "====================================="
    
    # Parse arguments
    CONFIG_FILE="${1:-config.conf}"
    DEPLOYMENT_NAME="${2:-}"
    TRAFFIC_PERCENTAGE="${3:-100}"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "❌ Config file '${CONFIG_FILE}' not found."
        usage
    fi
    
    # Validate traffic percentage
    if ! [[ "${TRAFFIC_PERCENTAGE}" =~ ^[0-9]+$ ]] || [[ "${TRAFFIC_PERCENTAGE}" -lt 0 ]] || [[ "${TRAFFIC_PERCENTAGE}" -gt 100 ]]; then
        echo "❌ Invalid traffic percentage: ${TRAFFIC_PERCENTAGE}. Must be between 0 and 100."
        exit 1
    fi
    
    # Source the config file
    echo "📖 Loading configuration from ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    
    # Use deployment name from config if not provided
    if [[ -z "${DEPLOYMENT_NAME}" ]]; then
        DEPLOYMENT_NAME="${AZ_DEPLOYMENT_NAME}"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Set Azure context
    echo "🔧 Setting Azure context..."
    az account set --subscription "${AZ_SUBSCRIPTION_ID}"
    az configure --defaults workspace="${AZ_ML_WORKSPACE}" group="${AZ_RESOURCE_GROUP}"
    echo "✅ Azure context set"
    
    # Check if endpoint exists
    if ! az ml online-endpoint show --name "${AZ_ENDPOINT_NAME}" &> /dev/null; then
        echo "❌ Endpoint ${AZ_ENDPOINT_NAME} not found."
        exit 1
    fi
    
    # Check if deployment exists
    if ! az ml online-deployment show --name "${DEPLOYMENT_NAME}" --endpoint-name "${AZ_ENDPOINT_NAME}" &> /dev/null; then
        echo "❌ Deployment ${DEPLOYMENT_NAME} not found in endpoint ${AZ_ENDPOINT_NAME}."
        exit 1
    fi
    
    echo ""
    echo "📋 Traffic Update Summary:"
    echo "========================="
    echo "Endpoint: ${AZ_ENDPOINT_NAME}"
    echo "Deployment: ${DEPLOYMENT_NAME}"
    echo "Traffic Percentage: ${TRAFFIC_PERCENTAGE}%"
    echo ""
    
    # Show current traffic allocation
    show_current_traffic
    
    # Confirm action
    read -p "Do you want to update traffic allocation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "ℹ️  Traffic allocation not changed"
        exit 0
    fi
    
   
    set_traffic_allocation "${DEPLOYMENT_NAME}" "${TRAFFIC_PERCENTAGE}"
    
    echo ""
    echo "🎉 Traffic Allocation Update Complete!"
}

# Show help if requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# Run main function
main "$@"
