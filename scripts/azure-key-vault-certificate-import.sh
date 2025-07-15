#!/bin/bash

# Sample execution command:
# ./azure-key-vault-certificate-import.sh \
#   -s "your-subscription-id" \
#   -v "your-keyvault-name" \
#   -g "your-resource-group" \
#   -c1 "path/to/cert1.pfx" \
#   -c2 "path/to/cert2.pfx" \
#   -c3 "path/to/cert3.pfx" \
#   -p "your-certificate-password"

# Script parameters
subscription_id=""
keyvault_name=""
keyvault_resource_group=""
cert1_path=""
cert2_path=""
cert3_path=""
cert_password=""

# Function to display usage
usage() {
    echo "Usage: $0"
    echo "  -s <subscription_id>        Azure subscription ID"
    echo "  -v <keyvault_name>         Name of the Azure Key Vault"
    echo "  -g <resource_group>        Resource group name of the Key Vault"
    echo "  -c1 <certificate1_path>    Path to first PFX certificate"
    echo "  -c2 <certificate2_path>    Path to second PFX certificate"
    echo "  -c3 <certificate3_path>    Path to third PFX certificate"
    echo "  -p <certificate_password>  Password for the PFX certificates"
    exit 1
}

# Parse command line arguments
while getopts "s:v:g:c1:c2:c3:p:" opt; do
    case $opt in
        s) subscription_id="$OPTARG" ;;
        v) keyvault_name="$OPTARG" ;;
        g) keyvault_resource_group="$OPTARG" ;;
        c1) cert1_path="$OPTARG" ;;
        c2) cert2_path="$OPTARG" ;;
        c3) cert3_path="$OPTARG" ;;
        p) cert_password="$OPTARG" ;;
        ?) usage ;;
    esac
done

# Validate required parameters
if [ -z "$subscription_id" ] || [ -z "$keyvault_name" ] || [ -z "$keyvault_resource_group" ] || \
   [ -z "$cert1_path" ] || [ -z "$cert2_path" ] || [ -z "$cert3_path" ] || [ -z "$cert_password" ]; then
    echo "Error: Missing required parameters"
    usage
fi

# Function to check if command was successful
check_error() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Login to Azure
echo "Logging in to Azure..."
az login
check_error "Failed to login to Azure"

# Set subscription
echo "Setting subscription..."
az account set --subscription "$subscription_id"
check_error "Failed to set subscription"

# Function to import certificate
import_certificate() {
    local cert_path=$1
    local cert_name=$(basename "$cert_path" .pfx)
    
    echo "Importing certificate: $cert_name"
    az keyvault certificate import \
        --vault-name "$keyvault_name" \
        --name "$cert_name" \
        --file "$cert_path" \
        --password "$cert_password"
    check_error "Failed to import certificate $cert_name"
}

# Import certificates
echo "Starting certificate import process..."
import_certificate "$cert1_path"
import_certificate "$cert2_path"
import_certificate "$cert3_path"

echo "Certificate import completed successfully!"