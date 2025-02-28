#!/bin/bash

# Function to stop a service if it exists
stop_service() {
    if systemctl is-active --quiet "$1" && systemctl is-enabled --quiet "$1"; then
        systemctl stop "$1"
        echo "Stopped service: $1"
    else
        echo "Service $1 not found, skipping."
    fi
}

# Stop services that should not be running in a template
echo "Stopping unnecessary services"
stop_service rsyslog
stop_service cron
if [[ -f /etc/redhat-release ]]; then
    service auditd stop
    echo "Stopped service: auditd using service command"
else
    stop_service auditd
fi

# Clean up logs
echo "Cleaning up logs"
find /var/log -type f ! -name 'yum.log' ! -name 'dnf.log' ! -path '/var/log/apt/*' -exec truncate -s 0 {} \;

# Create a oneshot systemd service to remove and recreate SSH keys
echo "Creating oneshot systemd service to reset SSH keys"
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
echo "Reloading systemd daemon"
systemctl daemon-reload
echo "Enabling SSH key reset service"
systemctl enable reset-ssh-keys.service

# Unset HISTFILE variable
echo "Unsetting HISTFILE variable"
unset HISTFILE
# Write current user's history to file
echo "Writing current user history to file"
history -w
# clear active user's history
echo "Clearing active user history"
history -c

# Clear shell history for all users
echo "Clearing shell history for all users"
awk -F: '($7 ~ /bash$/) {print $6}' /etc/passwd | while read home; do
    if [[ -n "$home" && -d "$home" ]]; then
        history_file="$home/.bash_history"
        if [[ -f "$history_file" ]]; then
            truncate -s 0 "$history_file"
        fi
    fi
done

# Clean up temporary files
echo "Cleaning up temporary files"
rm -rf /tmp/* /var/tmp/*

# Remove udev rules to avoid duplicate network interfaces
echo "Removing udev rules to prevent duplicate network interfaces"
rm -f /etc/udev/rules.d/70-persistent-net.rules

# Clean up machine ID
echo "Cleaning up machine ID"
truncate -s 0 /etc/machine-id
echo "Handling /var/lib/dbus/machine-id"
if [[ -f /var/lib/dbus/machine-id ]]; then
    rm -f /var/lib/dbus/machine-id
    ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

# Clear package manager cache
echo "Clearing package manager cache"
if [[ -f /etc/debian_version ]]; then
    apt-get clean  # For Debian/Ubuntu
elif [[ -f /etc/redhat-release ]]; then
    if grep -E "release [5-7]" /etc/redhat-release; then
        yum clean all  # For RHEL 7 and lower
    else
        dnf clean all  # For RHEL 8 and higher
    fi
fi

echo "Finalizing preparation: System prepared for VM template conversion."

# Schedule system shutdown
echo "Shutting down the system immediately"
shutdown now
