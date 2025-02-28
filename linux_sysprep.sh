#!/bin/bash

# Function to stop a service if it exists and is running
stop_service() {
    if systemctl is-active --quiet "$1" && systemctl is-enabled --quiet "$1"; then
        systemctl stop "$1"
        echo "Stopped service: $1"
    else
        echo "Service $1 not found, skipping."
    fi
}

# Stop services that should not be running while a template is created
stop_service rsyslog
stop_service cron
if [[ -f /etc/redhat-release ]]; then
    service auditd stop
    echo "Stopped service: auditd using service command"
else
    stop_service auditd
fi

# Clean up logs
find /var/log -type f -exec truncate -s 0 {} \;

# Create a oneshot systemd service to remove and recreate SSH keys
cat <<EOF > /etc/systemd/system/reset-ssh-keys.service
[Unit]
Description=Remove and regenerate SSH host keys
Before=ssh.service
After=network.target

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c 'rm -f /etc/ssh/ssh_host_*'
ExecStart=/bin/sh -c 'ssh-keygen -A'
ExecStartPost=/bin/sh -c 'systemctl disable reset-ssh-keys.service'

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl daemon-reload
systemctl enable reset-ssh-keys.service

# Unset HISTFILE variable
unset HISTFILE
# Write current user's history to file
history -w
# clear active user's history
history -c

# Clear shell history for all users
awk -F: '($7 ~ /bash$/) {print $6}' /etc/passwd | while read home; do
    if [[ -n "$home" && -d "$home" ]]; then
        history_file="$home/.bash_history"
        if [[ -f "$history_file" ]]; then
            truncate -s 0 "$history_file"
        fi
    fi
done

# Clean up temporary files
rm -rf /tmp/* /var/tmp/*

# Remove udev rules to avoid duplicate network interfaces
rm -f /etc/udev/rules.d/70-persistent-net.rules

# Clean up machine ID
truncate -s 0 /etc/machine-id
if [[ -f /var/lib/dbus/machine-id ]]; then
    rm -f /var/lib/dbus/machine-id
    ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

# Clear package manager cache
if [[ -f /etc/debian_version ]]; then
    apt-get clean  # For Debian/Ubuntu
elif [[ -f /etc/redhat-release ]]; then
    if grep -q "release [5-7]" /etc/redhat-release; then
        # For RHEL 7 and lower
        yum clean all
    else
        # For RHEL 8 and higher
        dnf clean all
    fi
fi

echo "System prepared for VM template conversion."

# Schedule system shutdown
echo "Shutting down the system immediately..."
shutdown now
