#!/usr/bin/with-contenv bash

# === Configuration Variables ===

# bindhost = host name
# bindlist = array of IP addresses (or '*' and '::' wildcards)
# ipaddrs  = comma-separated string form of bindlist

bindhost=$(hostname)

case ${LISTEN_ON:=host} in
	host) read -ra bindlist < <(hostname -i) ;;
	'*')  bindlist=('*' '::') ;;
	*)    read -ra bindlist <<<"${LISTEN_ON}" ;;
esac

ipaddrs=${bindlist[*]}; ipaddrs=${ipaddrs// /,}


# === Configure dovecot and nginx to bind or connect with the right IPs ===

# We only care about the hostname for connnecting to the submission port
sed -i 's/submission_host = .*:587$/submission_host = '"$bindhost:587/" /etc/dovecot/conf.d/15-lda.conf

if [[ "$LISTEN_ON" == host ]]; then
	# No IPs given, just use the hostname
	sed -i 's/__HOST__/'"$bindhost"/                        /etc/nginx/sites-enabled/administration
	sed -i 's/^#\?listen = .*/listen = '"${bindhost}/"      /etc/dovecot/dovecot.conf
else
	# We have explicit listening IPs (or wildcards): give them to dovecot and nginx
	sed -i 's/^#\?listen = .*/listen = '"${ipaddrs}/"       /etc/dovecot/dovecot.conf

	function add_nginx_listener() {
		# Add a listen line above the default one, for the specified address, port and options
		sed -i '/__HOST__:'"$2/i \\"$'\n'"    listen $1:$2${3+ $3};" /etc/nginx/sites-enabled/administration
	}

	for addr in "${bindlist[@]}"; do
		if [[ "$addr" == *:* ]]; then addr="[${addr}]"; fi  # nginx needs IPv6 addresses to be in '[]'
		add_nginx_listener "$addr" "$HTTP_PORT"
		add_nginx_listener "$addr" "$HTTPS_PORT" ssl
	done

	# delete the original listening lines we were using as insertion targets
	sed -i '/__HOST__:/d' /etc/nginx/sites-enabled/administration
fi


# === Haraka needs each IP address to be listed explicitly, unless you're using wildcards ===

if [[ $ipaddrs != *'*'* ]]; then
	listen025=${ipaddrs//,/:25,}:25
	listen465=${ipaddrs//,/:465,}:465
	listen587=${ipaddrs//,/:587,}:587

	sed -i 's/^listen=.*:25$/listen='"$listen025/"                    /opt/haraka-smtp/config/smtp.ini
	sed -i 's/^listen=.*:587,.*:465$/listen='"$listen587,$listen465/" /opt/haraka-submission/config/smtp.ini
fi

# Our Haraka sender-ip control plugin will validate outgoing IPs against the
# listening address list, and use the first address as the default (which may
# be '*', meaning "let the OS pick an outgoing IP".)

echo "$ipaddrs" >/opt/haraka-submission/config/my-ips
echo "$ipaddrs" >/opt/haraka-smtp/config/my-ips
