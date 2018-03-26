#!/bin/sh
# Ensure initial environment gets passed to ssh clients
env > /etc/environment
# Start the SSH Service
sed -i 's/PermitRootLogin.*/PermitRootLogin Yes/g' /etc/ssh/sshd_config
chmod 0700 ~/.ssh
chmod 0600 ~/.ssh/authorized_keys
ssh-keygen -q -t rsa -N '' -f /etc/ssh/ssh_host_rsa_key
exec /usr/sbin/sshd -D -p $SSH_PORT