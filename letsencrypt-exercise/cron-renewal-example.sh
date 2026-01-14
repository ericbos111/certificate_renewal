#!/bin/bash
# cron-renewal-example.sh
# Example cron job configuration for automated Let's Encrypt certificate renewal

# This file shows how to set up automated certificate renewal
# Add this to your crontab with: crontab -e

# ============================================
# CRON JOB EXAMPLES
# ============================================

# Option 1: Run renewal check twice daily (recommended by Let's Encrypt)
# This checks for certificates that need renewal and renews them if necessary
# Runs at midnight and noon every day
# 0 0,12 * * * /path/to/renew-letsencrypt.sh >> /var/log/letsencrypt-renewal.log 2>&1

# Option 2: Run renewal check once daily at 3 AM
# 0 3 * * * /path/to/renew-letsencrypt.sh >> /var/log/letsencrypt-renewal.log 2>&1

# Option 3: Run renewal check weekly on Sunday at 2 AM
# 0 2 * * 0 /path/to/renew-letsencrypt.sh >> /var/log/letsencrypt-renewal.log 2>&1

# Option 4: Just run certbot renew (without OpenShift update)
# 0 0,12 * * * certbot renew --quiet --post-hook "systemctl reload nginx"

# ============================================
# SYSTEMD TIMER ALTERNATIVE (Modern Linux)
# ============================================

# Instead of cron, you can use systemd timers
# Create these files:

# /etc/systemd/system/letsencrypt-renewal.service
cat << 'EOF'
[Unit]
Description=Let's Encrypt Certificate Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/path/to/renew-letsencrypt.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# /etc/systemd/system/letsencrypt-renewal.timer
cat << 'EOF'
[Unit]
Description=Let's Encrypt Certificate Renewal Timer
Requires=letsencrypt-renewal.service

[Timer]
OnCalendar=daily
OnCalendar=12:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer:
# sudo systemctl enable letsencrypt-renewal.timer
# sudo systemctl start letsencrypt-renewal.timer
# sudo systemctl status letsencrypt-renewal.timer

# ============================================
# MONITORING AND ALERTING
# ============================================

# Add monitoring to check certificate expiration
# Example: Send email alert if certificate expires in less than 7 days

cat << 'EOF'
#!/bin/bash
# check-cert-expiration.sh

DOMAIN="yourdomain.com"
# Alert 7 days before expiration to allow time for manual intervention if automated renewal fails
ALERT_DAYS=7
EMAIL="admin@example.com"

# Get certificate expiration date
EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | \
         openssl x509 -noout -enddate | cut -d= -f2)

# Convert to epoch time (with platform detection)
if date --version >/dev/null 2>&1; then
    # GNU date
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
else
    # BSD date (macOS)
    EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s)
fi
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

if [ $DAYS_LEFT -lt $ALERT_DAYS ]; then
    echo "WARNING: Certificate for $DOMAIN expires in $DAYS_LEFT days!" | \
    mail -s "Certificate Expiration Alert" $EMAIL
fi
EOF

# Add to crontab to run daily:
# 0 9 * * * /path/to/check-cert-expiration.sh

# ============================================
# KUBERNETES CRONJOB (for cert-manager alternative)
# ============================================

cat << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: letsencrypt-renewal
  namespace: letsencrypt-demo
spec:
  schedule: "0 0,12 * * *"  # Twice daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: letsencrypt-renewal
          containers:
          - name: renewal
            image: quay.io/openshift/origin-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              # Your renewal script here
              /scripts/renew-letsencrypt.sh
            volumeMounts:
            - name: renewal-script
              mountPath: /scripts
          restartPolicy: OnFailure
          volumes:
          - name: renewal-script
            configMap:
              name: renewal-script
              defaultMode: 0755
EOF

echo ""
echo "================================================"
echo "Cron Renewal Configuration Examples"
echo "================================================"
echo ""
echo "To set up automated renewal:"
echo "1. Edit your crontab: crontab -e"
echo "2. Add one of the cron job examples above"
echo "3. Save and exit"
echo ""
echo "To verify cron job is set:"
echo "  crontab -l"
echo ""
echo "To view renewal logs:"
echo "  tail -f /var/log/letsencrypt-renewal.log"
echo ""
echo "For systemd timers (recommended on modern Linux):"
echo "  sudo systemctl enable letsencrypt-renewal.timer"
echo "  sudo systemctl start letsencrypt-renewal.timer"
echo ""

# Made with Bob
