'use strict';

/*****

This plugin detects local connections from listening IPs, and changes the remote
IP to 127.0.0.1, simulating a local connection.  Many of poste.io's plugins
have 127.0.0.1 hardcoded for special handling that otherwise might not be applied
when using this image.

*****/

const listening_ips = require("haraka-config").get("listen-ips").trim().split(/\s*,\s*/);
const is_local = listening_ips.reduce((map, addr)=>{map[addr]=true; return map;}, {});

exports.hook_connect_init = function(next, connection) {
    if ( is_local[connection.remote.ip] ) {
        this.logdebug(`localhost connection from ${connection.remote.ip}`);
        connection.remote.ip = '127.0.0.1';
    }
    return next();
}
