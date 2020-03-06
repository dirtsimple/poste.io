#!/usr/bin/with-contenv bash

# === Configure dovecot and nginx to bind or connect via the container's hostname ===

bindhost=$(hostname)
sed -i 's/__HOST__/'"$bindhost"/                                        /etc/nginx/sites-enabled/administration
sed -i 's/submission_host = .*:587$/submission_host = '"$bindhost:587/" /etc/dovecot/conf.d/15-lda.conf


# === Haraka needs each IP address to be listed explicitly ===

ipaddrs=$(hostname -i)
listen025=${ipaddrs// /:25,}:25
listen465=${ipaddrs// /:465,}:465
listen587=${ipaddrs// /:587,}:587

sed -i 's/^listen=.*:25$/listen='"$listen025/"                    /opt/haraka-smtp/config/smtp.ini
sed -i 's/^listen=.*:587,.*:465$/listen='"$listen587,$listen465/" /opt/haraka-submission/config/smtp.ini

outbound=${ipaddrs// /,}
echo "$outbound" >/opt/haraka-submission/config/my-ips
echo "$outbound" >/opt/haraka-smtp/config/my-ips

