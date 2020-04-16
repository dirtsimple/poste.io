#!/usr/bin/with-contenv bash

# Given a variable name and setting, get the matching IP addresses as a comma-delimited list
function ip_list() {
	local -n ips=$1
	case $2 in
		host) ips=$(hostname -i) ;;
		'*')  ips='* ::' ;;
		*)    read -ra ips <<<"$2"; ips=("${ips[*]}") ;;  # trim/normalize whitespace
	esac
	ips="${ips// /,}"; ips=${ips:-*,::}  # handle empty list
}

# Expand LISTEN_ON and SEND_ON into comma-delimited IP lists in `listen` and `send`
ip_list listen "${LISTEN_ON:=host}"
ip_list send   "${SEND_ON:=${listen//,/ }}"

# Do simple sed subtitutions (assumes '"' not present in pattern/replacement strings)
function sub() { sed -i 's"'"$1"'"'"$2"'"' "$3"; }     # replace $1 w/$2 in $3
function ins() { sed -i '\"'"$1"$'"i \\\n'"$2" "$3"; } # insert $2 before $1 in $3
function del() { sed -i '\"'"$1"'"d' "$2"; }           # delete lines matching $1 from $2


# === Configure dovecot and nginx to bind or connect with the right IPs ===

bindhost=$(hostname)

# We only care about the hostname for connnecting to the submission port
sub 'submission_host = .*:587$' "submission_host = $bindhost:587" /etc/dovecot/conf.d/15-lda.conf

if [[ "$LISTEN_ON" == host ]]; then
	# No IPs given, just use the hostname
	sub '__HOST__'        "$bindhost"                 /etc/nginx/sites-enabled/administration
	sub '^#\?listen = .*' "listen = ${bindhost}"      /etc/dovecot/dovecot.conf
else
	# We have explicit listening IPs (or wildcards): give them to dovecot and nginx
	sub '^#\?listen = .*' "listen = ${listen}"        /etc/dovecot/dovecot.conf

	IFS=, read -ra ipaddrs <<<"$listen"
	for addr in "${ipaddrs[@]}"; do
		if [[ "$addr" == *:* ]]; then addr="[${addr}]"; fi  # nginx needs IPv6 addresses to be in '[]'
		# Add listen lines above the default ones, for the specified address, port and options
		ins "__HOST__:$HTTP_PORT"  "    listen $addr:$HTTP_PORT;"      /etc/nginx/sites-enabled/administration
		ins "__HOST__:$HTTPS_PORT" "    listen $addr:$HTTPS_PORT ssl;" /etc/nginx/sites-enabled/administration
	done

	# delete the original listening lines we were using as insertion targets
	del '__HOST__:' /etc/nginx/sites-enabled/administration
fi


# === Haraka needs each IP address to be listed explicitly, unless you're using wildcards ===

if [[ $listen != *'*'* ]]; then
	sub '^listen=.*:25$'         "listen=${listen//,/:25,}:25"                          /opt/haraka-smtp/config/smtp.ini
	sub '^listen=.*:587,.*:465$' "listen=${listen//,/:587,}:587,${listen//,/:465,}:465" /opt/haraka-submission/config/smtp.ini
else
	listen=::0
fi

# Our Haraka sender-ip control plugin will validate outgoing IPs against the
# sending address list, and use the first address as the default (which may
# be '*', meaning "let the OS pick an outgoing IP".)

echo "$send" >/opt/haraka-submission/config/my-ips
echo "$send" >/opt/haraka-smtp/config/my-ips

# Our inbound IP plugin will translate local connections to 127.0.0.1

echo "$listen" >/opt/haraka-submission/config/listen-ips
echo "$listen" >/opt/haraka-smtp/config/listen-ips
