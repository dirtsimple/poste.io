'use strict';

/*****

This plugin selects an outbound IP address for each piece of outgoing mail,
using the following algorithm:

* If only one IP address is known for the container's hostname (as of container
  start), use that address for everything.
* If an environment variable 'OUTBOUND_MAIL_IP' exists, use it for everything.
* Check the contents of /data/outbound-hosts.yml for an entry for the sender's
  domain (which should be an object with 'helo' and 'ip' props), or a 'default'
  entry if there's no entry for the domain.  If the file can't be read or parsed,
  or an entry is malformed, fall through to the next step.
* If an environment variable 'OUTBOUND_DEFAULT_IP' exists, use that
* Use the first IP address mapped to the container's hostname

In the future, the .yml file lookup would be best replaced with SQLite database
columns on the domains table (for HELO name and IP).  The configuration could
then be done via the admin interface.

*****/

const fs  = require('fs').promises;
const yml = require('js-yaml');

const hostname = require('os').hostname();

const my_ips = require("haraka-config").get("my-ips").trim().split(/\s*,\s*/);
const default_ip = process.env.OUTBOUND_MAIL_IP || my_ips[0];

const have_ip = my_ips.reduce((map, addr)=>{map[addr]=true; return map;}, {});

exports.hook_get_mx = async function(next, hmail, domain) {
    const plugin = this;

    function set_outbound(items, key) {
        const target = items[key];
        if ( 'object' !== typeof target ||
             'string' !== typeof target.helo ||
             'string' !== typeof target.ip
        ) {
            const errmsg = `${key} must be an object with 'helo' and 'ip' strings: got ${JSON.stringify(target)}`;
            throw new Error(errmsg);
        }

        // '*' means "let the OS pick an IP for the target route"
        if (target.ip === '*') return;

        if (!have_ip[target.ip] && !have_ip['*'] && target.ip !== default_ip) {
            throw new Error(`${key}: ${ip} is not a listed address for this server instance`);
        }

        plugin.loginfo(`Setting outbound HELO = ${target.helo}, IP = ${target.ip} (${key})`);
        hmail.todo.notes.outbound_helo = target.helo;
        hmail.todo.notes.outbound_ip   = target.ip;
    }

    function use_default() {
        set_outbound({"default": {helo: hostname, ip: default_ip}}, 'default');
    }

    if ( process.env.OUTBOUND_MAIL_IP || my_ips.length === 1 ) {
        use_default();
    } else {
        const from_domain = hmail.todo.mail_from.host;

        try {
            this.logdebug("loading /data/outbound-hosts.yml");
            const outbound = yml.safeLoad(
                await fs.readFile('/data/outbound-hosts.yml','utf8')
            );
            if ( outbound[from_domain] ) {
                set_outbound(outbound, from_domain);
            }
            else if ( outbound['default'] ) {
                set_outbound(outbound, 'default');
            }
            else {
                this.logerror(`Couldn't find an entry for ${from_domain} or 'default' in  /data/outbound-hosts.yml`);
                use_default();
            }
        } catch (err) {
            // Fall back to default IP
            this.logerror(`Error using /data/outbound-hosts.yml: ${err.message}`);
            use_default();
        }
    }

    next();
}
