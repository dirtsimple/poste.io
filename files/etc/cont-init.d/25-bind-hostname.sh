#!/usr/bin/with-contenv bash

# === Configure Haraka and nginx to use only the container's hostname ==

bindhost=$(hostname)

sed -i 's/__HOST__/'"$bindhost"/                                        /etc/nginx/sites-enabled/administration
sed -i 's/^listen=.*:25$/listen='"$bindhost/"                           /opt/haraka-smtp/config/smtp.ini
sed -i 's/^listen=.*:587,.*:465$/listen='"$bindhost:587,$bindhost:465/" /opt/haraka-submission/config/smtp.ini

# Haraka should only do outbound connects on our IP
hostname -i >/opt/haraka-submission/config/my-ip
hostname -i >/opt/haraka-smtp/config/my-ip

