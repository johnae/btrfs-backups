#!/bin/sh
# Ensure initial environment gets passed to ssh clients
env > /etc/environment
# Start the SSH Service
sed -i 's/PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
chmod 0700 ~/.ssh
chmod 0600 ~/.ssh/authorized_keys
if [ ! -e "/storage/ssh_host_rsa_key" ]; then
    ssh-keygen -q -t rsa -N '' -f /storage/ssh_host_rsa_key
fi
cp /storage/ssh_host_rsa_key /etc/ssh/
exec /usr/sbin/sshd -e -D -p $SSH_PORT
