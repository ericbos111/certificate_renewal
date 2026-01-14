#!/bin/bash
# renew-letsencrypt.sh
# Script to renew Let's Encrypt certificates and update OpenShift secrets
# Required permissions:
# - sudo access for certbot certificate renewal operations
# - OpenShift permissions for secret/pod management in target namespace
#   (specifically: secrets get/create/delete, pods get/delete)

set -e

# Cleanup temporary files on exit
trap 'rm -f ./tls.crt ./tls.key' EXIT ERR

# Configuration
DOMAIN="${DOMAIN:-yourdomain.com}"
NAMESPACE="${NAMESPACE:-letsencrypt-demo}"
SECRET_NAME="${SECRET_NAME:-todo-letsencrypt-secret}"
DEPLOYMENT="${DEPLOYMENT:-todo-angular}"
CERT_PATH="${CERT_PATH:-/etc/letsencrypt/live/$DOMAIN}"
TIMEOUT="${TIMEOUT:-60s}"

# Validate domain is not the default placeholder
if [ "$DOMAIN" = "yourdomain.com" ]; then
    echo "ERROR: Domain is still set to the default placeholder 'yourdomain.com'"
    echo "Please set the DOMAIN environment variable to your actual domain:"
    echo "  export DOMAIN=your-actual-domain.com"
    echo "  $0"
    exit 1
fi

# Validate domain format
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
    echo "ERROR: Invalid domain format: $DOMAIN"
    echo "Domain must be a valid format (e.g., example.com, sub.example.com)"
    exit 1
fi

# Validate namespace format (alphanumeric, hyphens only)
if [[ ! "$NAMESPACE" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
    echo "ERROR: Invalid namespace format: $NAMESPACE"
    echo "Namespace must contain only alphanumeric characters and hyphens"
    exit 1
fi

# Validate secret name format (alphanumeric, hyphens only)
if [[ ! "$SECRET_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
    echo "ERROR: Invalid secret name format: $SECRET_NAME"
    echo "Secret name must contain only alphanumeric characters and hyphens"
    exit 1
fi

# Validate deployment name format (alphanumeric, hyphens only)
if [[ ! "$DEPLOYMENT" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
    echo "ERROR: Invalid deployment name format: $DEPLOYMENT"
    echo "Deployment name must contain only alphanumeric characters and hyphens"
    exit 1
fi

echo "=== Let's Encrypt Certificate Renewal Script ==="
echo "Domain: $DOMAIN"
echo "Namespace: $NAMESPACE"
echo "Secret: $SECRET_NAME"
echo ""

# Check if running as root for certbot
if [ "$EUID" -ne 0 ]; then 
    echo "Warning: This script may need sudo privileges for certbot"
fi

# Renew certificate
echo "Step 1: Renewing Let's Encrypt certificate..."
sudo certbot renew --quiet --cert-name "$DOMAIN"

if [ $? -eq 0 ]; then
    echo "✓ Certificate renewed successfully"
else
    echo "✗ Certificate renewal failed"
    exit 1
fi

# Copy certificates to current directory
echo ""
echo "Step 2: Copying certificates..."

# Check if certificate files exist before copying
if [ ! -f "$CERT_PATH/fullchain.pem" ]; then
    echo "Error: Certificate file not found: $CERT_PATH/fullchain.pem"
    exit 1
fi

if [ ! -f "$CERT_PATH/privkey.pem" ]; then
    echo "Error: Private key file not found: $CERT_PATH/privkey.pem"
    exit 1
fi

sudo cp "$CERT_PATH/fullchain.pem" ./tls.crt
sudo cp "$CERT_PATH/privkey.pem" ./tls.key
sudo chmod 644 tls.crt && sudo chmod 600 tls.key
echo "✓ Certificates copied"

# Check if logged into OpenShift
echo ""
echo "Step 3: Checking OpenShift connection..."
if ! oc whoami &> /dev/null; then
    echo "✗ Not logged into OpenShift. Please run 'oc login' first"
    exit 1
fi
echo "✓ Connected to OpenShift as $(oc whoami)"

# Switch to namespace
echo ""
echo "Step 4: Switching to namespace $NAMESPACE..."
oc project "$NAMESPACE" || {
    echo "✗ Failed to switch to namespace $NAMESPACE"
    exit 1
}
echo "✓ Using namespace $NAMESPACE"

# Update secret in-place
echo ""
echo "Step 5: Updating secret with renewed certificate..."
# Check if secret exists, create if not
if ! oc get secret "$SECRET_NAME" &> /dev/null; then
    echo "Secret does not exist, creating new secret..."
    oc create secret tls "$SECRET_NAME" --cert=tls.crt --key=tls.key
else
    echo "Updating existing secret..."
    oc create secret tls "$SECRET_NAME" --cert=tls.crt --key=tls.key --dry-run=client -o yaml | oc apply -f -
fi
echo "✓ Secret updated"

# Restart pods
echo ""
echo "Step 6: Restarting pods to pick up new certificate..."
oc rollout restart deployment/$DEPLOYMENT
echo "✓ Rolling restart initiated"

# Wait for rollout to complete
echo ""
echo "Step 7: Waiting for rollout to complete..."
oc rollout status deployment/$DEPLOYMENT --timeout=$TIMEOUT

# Verify all replicas are ready
EXPECTED=$(oc get deployment $DEPLOYMENT -o jsonpath='{.spec.replicas}')
READY=$(oc get deployment $DEPLOYMENT -o jsonpath='{.status.readyReplicas}')
if [ "$READY" != "$EXPECTED" ]; then
    echo "✗ Rollout incomplete: $READY/$EXPECTED replicas ready"
    exit 1
fi
echo "✓ Rollout complete: $READY/$EXPECTED replicas ready"

# Verify certificate
echo ""
echo "Step 8: Verifying certificate expiration..."
ROUTE=$(oc get route "$DEPLOYMENT" -o jsonpath='{.spec.host}')
if [ -n "$ROUTE" ]; then
    echo "Route: https://$ROUTE"
    echo ""
    if ! openssl s_client -connect "$ROUTE:443" -servername "$ROUTE" </dev/null 2>/dev/null | \
        openssl x509 -noout -dates 2>/dev/null; then
        echo "✗ Warning: Could not verify certificate - verification failed"
        echo "  The certificate may not be properly installed or the route may not be accessible"
    fi
else
    echo "Warning: Could not find route"
fi

echo ""
echo "=== Certificate Renewal Complete ==="
echo "Certificate renewed and deployed successfully!"

# Cleanup temporary certificate files
echo ""
echo "Cleaning up temporary certificate files..."
rm -f ./tls.crt ./tls.key
echo "✓ Temporary files removed"

# Made with Bob
