# Certificate Renewal with Let's Encrypt

## What Is Let's Encrypt?
Let's Encrypt is a free, automated, and open Certificate Authority (CA) that provides SSL/TLS certificates. Unlike self-signed certificates, Let's Encrypt certificates are trusted by all major browsers and operating systems. Let's Encrypt certificates expire after 90 days, encouraging automation and regular renewal practices.

## Why Use Let's Encrypt?
- **Free**: No cost for certificates
- **Automated**: Designed for automated certificate issuance and renewal
- **Trusted**: Certificates are trusted by all major browsers
- **Short-lived**: 90-day validity encourages best practices and automation

## In this exercise we will simulate an application with Let's Encrypt certificate renewal

### Prerequisites
- OpenShift cluster access
- `certbot` or `acme.sh` client installed (for Let's Encrypt)
- A domain name that you control (for DNS validation)
- `oc` CLI tool installed and configured

### Exercise Steps

#### 1. Install Certbot (Let's Encrypt Client)

For RHEL/CentOS/Fedora:
```bash
sudo dnf install certbot
```

For Ubuntu/Debian:
```bash
sudo apt-get install certbot
```

Alternatively, use the standalone certbot-auto script:
```bash
wget https://dl.eff.org/certbot-auto
chmod +x certbot-auto
```

#### 2. Obtain a Let's Encrypt Certificate

**Option A: Using DNS Challenge (Recommended for OpenShift)**

This method works well when you don't have direct HTTP access to port 80:

```bash
# Request certificate using DNS challenge
sudo certbot certonly --manual --preferred-challenges dns -d yourdomain.com

# Follow the prompts to add TXT records to your DNS
# Certbot will provide the TXT record values you need to add
```

**Option B: Using HTTP Challenge (Requires Port 80 Access)**

```bash
# Request certificate using standalone HTTP server
sudo certbot certonly --standalone -d yourdomain.com
```

**Option C: Using Webroot (If You Have an Existing Web Server)**

```bash
# Request certificate using webroot
sudo certbot certonly --webroot -w /var/www/html -d yourdomain.com
```

After successful validation, your certificates will be stored in:
- Certificate: `/etc/letsencrypt/live/yourdomain.com/fullchain.pem`
- Private Key: `/etc/letsencrypt/live/yourdomain.com/privkey.pem`

#### 3. Deploy the Application in OpenShift

Create a new project:
```bash
oc new-project letsencrypt-demo
```

Deploy the secure todo application:
```bash
oc new-app quay.io/redhattraining/todo-angular:v1.2
```

Create a passthrough route:
```bash
oc create route passthrough todo-angular --service=todo-angular --port 8443
```

#### 4. Create Secret with Let's Encrypt Certificate

The application expects certificates at `/usr/local/etc/ssl/certs/`. Create a TLS secret:

```bash
# Copy certificates from Let's Encrypt directory
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ./tls.crt
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ./tls.key
sudo chmod 644 tls.crt tls.key

# Create the secret in OpenShift
oc create secret tls todo-letsencrypt-secret --cert=tls.crt --key=tls.key
```

#### 5. Mount the Secret as a Volume

```bash
oc set volume deployment/todo-angular \
  --add \
  --type secret \
  --mount-path /usr/local/etc/ssl/certs \
  --secret-name todo-letsencrypt-secret \
  --read-only
```

#### 6. Verify the Application and Certificate

Get the route:
```bash
oc get route todo-angular
```

Test the application:
```bash
# Test connectivity
curl -k https://<route-hostname>

# Check certificate details
openssl s_client -connect <route-hostname>:443 -showcerts | grep -A 2 "Validity"
```

You should see the certificate is valid for 90 days from the issue date.

#### 7. Simulate Certificate Expiration (Optional)

To test the renewal process without waiting 90 days, you can:

1. Request a test certificate with shorter validity:
```bash
# Let's Encrypt staging environment (for testing)
sudo certbot certonly --staging --manual --preferred-challenges dns -d yourdomain.com
```

2. Or manually create a short-lived certificate for testing:
```bash
# Create a 1-day certificate for testing
openssl req -new -key tls.key -out tls.csr
openssl x509 -req -in tls.csr -signkey tls.key -out tls.crt -days 1
```

#### 8. Renew the Let's Encrypt Certificate

Let's Encrypt certificates should be renewed before they expire. The recommended practice is to renew when there are 30 days or less remaining.

**Manual Renewal:**
```bash
# Renew all certificates that are due for renewal
sudo certbot renew

# Or renew a specific certificate
sudo certbot renew --cert-name yourdomain.com
```

**Automated Renewal (Recommended):**

Set up a cron job for automatic renewal:
```bash
# Edit crontab
sudo crontab -e

# Add this line to check for renewal twice daily
0 0,12 * * * certbot renew --quiet --post-hook "systemctl reload nginx"
```

For OpenShift, create a renewal script:
```bash
#!/bin/bash
# renew-letsencrypt.sh

# Renew certificate
sudo certbot renew --quiet

# Copy new certificates
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ./tls.crt
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ./tls.key
sudo chmod 644 tls.crt tls.key

# Update OpenShift secret
oc delete secret todo-letsencrypt-secret -n letsencrypt-demo
oc create secret tls todo-letsencrypt-secret --cert=tls.crt --key=tls.key -n letsencrypt-demo

# Restart pods to pick up new certificate
oc delete pod -l deployment=todo-angular -n letsencrypt-demo

echo "Certificate renewed and deployed successfully"
```

Make it executable:
```bash
chmod +x renew-letsencrypt.sh
```

#### 9. Update the Secret in OpenShift

After renewal, update the secret:
```bash
# Delete old secret
oc delete secret todo-letsencrypt-secret

# Create new secret with renewed certificate
oc create secret tls todo-letsencrypt-secret --cert=tls.crt --key=tls.key

# Delete pods to force recreation with new certificate
oc delete pod -l deployment=todo-angular
```

#### 10. Verify the Renewed Certificate

```bash
# Check the new certificate expiration
openssl s_client -connect <route-hostname>:443 -showcerts 2>/dev/null | openssl x509 -noout -dates

# Test application access
curl -k https://<route-hostname>
```

You should see the certificate is now valid for another 90 days.

## Automation with cert-manager (Advanced)

For production environments, consider using [cert-manager](https://cert-manager.io/) in OpenShift/Kubernetes:

1. Install cert-manager:
```bash
oc apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

2. Create a ClusterIssuer for Let's Encrypt:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

3. Create a Certificate resource:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: todo-angular-cert
  namespace: letsencrypt-demo
spec:
  secretName: todo-letsencrypt-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - yourdomain.com
```

cert-manager will automatically handle certificate issuance and renewal!

## Key Differences from Self-Signed Certificates

| Aspect | Self-Signed | Let's Encrypt |
|--------|-------------|---------------|
| Trust | Not trusted by browsers | Trusted by all major browsers |
| Cost | Free | Free |
| Validity | Custom (1 day to years) | 90 days (fixed) |
| Renewal | Manual | Automated (recommended) |
| Use Case | Development/Testing | Production |
| CA Chain | No chain | Full chain included |

## Best Practices

1. **Automate Renewal**: Set up automated renewal at least 30 days before expiration
2. **Monitor Expiration**: Use monitoring tools to alert on upcoming expirations
3. **Test Renewals**: Regularly test your renewal process in staging
4. **Use cert-manager**: For Kubernetes/OpenShift, use cert-manager for full automation
5. **Keep Backups**: Maintain backups of your Let's Encrypt account keys
6. **Rate Limits**: Be aware of Let's Encrypt rate limits (50 certificates per domain per week)

## Troubleshooting

### Certificate Request Failed
- Check DNS records are correct and propagated
- Verify firewall rules allow HTTP/HTTPS traffic
- Ensure domain ownership can be validated

### Certificate Not Trusted
- Verify you're using production Let's Encrypt server (not staging)
- Check that fullchain.pem is used (includes intermediate certificates)

### Renewal Failed
- Check certbot logs: `/var/log/letsencrypt/letsencrypt.log`
- Verify DNS/HTTP validation still works
- Ensure sufficient time before expiration (renewal window)

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot Documentation](https://certbot.eff.org/docs/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [OpenShift Routes and Certificates](https://docs.openshift.com/container-platform/latest/networking/routes/secured-routes.html)

![Let's Encrypt Logo](https://letsencrypt.org/images/letsencrypt-logo-horizontal.svg)