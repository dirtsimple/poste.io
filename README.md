## Enhanced Poste.io (IP Management & Roundcube Plugins)

[poste.io](https://poste.io) is a pretty cool email server implementation for docker.  But this image makes it *cooler*.

Specifically, it lets you:

* Use host-mode networking and still:
  * Run things besides poste on the same server without localhost port conflicts
  * Have multiple poste instances (e.g. dev and prod) running on the same server, listening on different IPs
  * Restrict which IP addresses poste listens on, so non-poste mail servers can run on the same server
  * Select which IP addresses poste *sends* mail from, [on a domain-by-domain basis](#managing-sender-ips)
* Install and use [custom Roundcube plugins](#using-custom-roundcube-plugins) from the `/data` volume
* Optionally [use a persistent `DES_KEY`](#the-des_key-variable) for Roundcube, to support plugins that store encrypted data

#### Contents

<!-- toc -->

- [Why Is This Image Needed?](#why-is-this-image-needed)
- [Basic Usage](#basic-usage)
- [Managing Hostnames and IP Addresses](#managing-hostnames-and-ip-addresses)
  * [Vanity or Private-Label Logins](#vanity-or-private-label-logins)
  * [Separate IPs for Different Domains](#separate-ips-for-different-domains)
- [Managing Sender IPs](#managing-sender-ips)
- [IPv6 Support](#ipv6-support)
- [Using Custom Roundcube Plugins](#using-custom-roundcube-plugins)
  * [The DES_KEY Variable](#the-des_key-variable)
- [Can I use these changes with poste.io's PRO version?](#can-i-use-these-changes-with-posteios-pro-version)
- [Docker Tags](#docker-tags)

<!-- tocstop -->

### Why Is This Image Needed?

One of the big challenges of using the stock poste image with host-mode networking (the poste.io recommended configuration) is that it doesn't play well with other mail servers on the same machine.  (Which makes it hard to e.g., have both a development and production instance, or to provide service to multiple clients on one machine.)

Specifically, in host mode networking, poste.io binds its outward-facing services to *every* IP address of the machine, *and* binds several of its internal services to localhost ports (6379, 11332-11334, 11380, 11381, and 13001), which can conflict with things *besides* mail servers or other poste.io instances.

As a result, poste.io not only doesn't play well with other mail servers (including other instances of itself), it *also* doesn't play well with being used on a server that *does anything else*.  (It almost might as well not be a docker container at all, in such a setup!)  And last, but not least, it sends email *out* on any old IP address as well, with no way to choose which IP you actually want to send things on.

So, this image fixes these issues by adding support for two environment variables and a configuration file, that let you not only control which IPs poste will listen on, but also which addresses poste will *send* mail on, optionally on a per-domain basis.  (Plus, it patches poste.io's default configuration so that all its internal services use unix domain sockets *inside* the docker container, instead of tying up localhost ports on the main server.)

The first variable it adds is `LISTEN_ON`, which can be set to either a list of specific IP addresses to listen on, `host` (to listen only on addresses bound to the container's hostname), or `*` (for poste's default behavior of listening on every available interface).

The second variable is `SEND_ON`, which can also be set to a list of IP addresses, `host`, or `*`.  (If unset or empty, it defaults to the value set in `LISTEN_ON`.)  By default, mail will be sent from the first IP address in the resulting list, unless it's `*`, in which case the operating system will pick the IP.  If there's only one sending IP,  all mail will be sent from the default IP.  Otherwise, a [configuration file](#managing-sender-ips) will be used to pick an IP address from the list, based on the domain the mail is being sent from.

### Basic Usage

To use this image, just replace `analogic/poste.io` in your config with `dirtsimple/poste.io`.  For example, you might use something like this as your `docker-compose.yml`, replacing `mail.example.com` with a suitable hostname  for your installation:

```yaml
version: "2.3"
services:
  poste:
    image: dirtsimple/poste.io
    restart: always
    network_mode: host  # <-- a must-have for poste

    # serve everything on `mail.example.com`, which will be the default HELO as well:
    hostname: mail.example.com

    volumes:
      - ./data:/data
      - /etc/localtime:/etc/localtime:ro

    # ==== Optional settings below: you don't need any environment vars by default ====

    environment:
      # Whitespace-separated list of IP addresses to listen on. If this variable
      # is set to "host" (which is also the default if it's empty or unset), the
      # container will listen on all the IPs (v4 and v6) found in DNS or /etc/hosts
      # for the container's hostname.  Or it can be set to "*", to listen on ALL
      # available addresses (the way the standard poste.io image does).
      - "LISTEN_ON=1.2.3.4 5.6.7.8 90a:11:12::13"

      # Whitespace-separated list of IP addresses mail can be sent from; the first
      # one in the list will be the default.  Like LISTEN_ON, it can be set to '*'
      # for "any available address" or 'host' for "any IP (v4 or v6) attached to
      # the container hostname".  If the list expands to only one address, it
      # will be used for all outgoing mail.  Otherwise, data/outbound-hosts.yml
      # is read to determine the outgoing IP for each domain, and the result is
      # validated against this list.  If this variable is empty or unset, it defaults
      # to whatever LISTEN_ON was set to.
      - "SEND_ON=9.10.11.12"

      # Other standard poste.io vars can also be used, e.g. HTTPS_PORT, etc.

```

Take note of the following, however:

* You **must** configure the container with a fully-qualified hostname (e.g. `mail.example.com` above), with at least one IP address listed in the public DNS system
* The hostname's IP addresses (or those listed in `LISTEN_ON`) must be public IPs attached to the server hosting the container
* The listening IPs must *not* have any other services listening on ports 25, 80, 110, 143, 443, 466, 587, 993, 995, or 4190.  (Though you can change or disable some of those ports using poste.io's environment variables.)
* You should be using **host-mode networking** (`network_mode: host` as shown above), since in any other networking mode, this image will behave roughly the same as the original `analogic/poste.io` image, and have the same limitations and caveats.  (Specifically, using any other networking mode means putting specific IP addresses into `LISTEN_ON`, `SEND_ON`, or `outbound-hosts.yml` will not do anything useful!)
* By default, outgoing email to other mail servers will be sent via the first IP address found in `LISTEN_ON` or returned by running `hostname -i` in the container.  If you need to override this behavior, configure the container with `SEND_ON` set to the specific IP address to be used, OR create a `/data/outbound-hosts.yml` file as described in [Managing Sender IPs](#managing-sender-ips) below.
* Connections *from* a listening IP will be treated as if they are connections from 127.0.0.1 (because they are from the local host) unless you're using `LISTEN_ON=*` mode.  This disables certain host-specific spam checks (e.g. asn, fcrdns, karma/history, etc.), that would otherwise apply.  This special behavior is *not* enabled for IPs that are used only for outgoing mail transmission; such IPs will be treated as normal unless you explicitly add them to your relay networks list.

Notice, by the way, that there are **no port mappings** used in this example, because the container uses host-mode networking and thus has direct access to all of the server's network interfaces.  This means that the IP addresses to be used by the container must be explicitly defined (either by the DNS address(es) of the hostname, or by setting the `LISTEN_ON` variable to the exact IP addresses) so that the container doesn't take over every IP address on the server.  (Unless that's what you *want*, in which case you can set `LISTEN_ON` to `*`.)

### Managing Hostnames and IP Addresses

In the simplest cases, an installation of this image would only need to use one hostname and IP, and:

* The hostname would be set as the MX record of any domains to be hosted on the instance
* Reverse DNS for the IP would point to the hostname
* The default TLS certificate generated by the image would suffice
* Users would log into webmail and admin using the single, primary hostname

In more complex setups, you may wish to use multiple IPs or hostnames, for example to give each domain its own `mail.somedomain.com` website and/or MX, or to separate the sending reputation of different domains, while keeping to a single container.  These scenarios *can* be done, but note that it is not possible to 100% hide the fact that all the domains are being served by the same container, as the TLS certificate used for both the web interface and SMTP will list all the hostnames sharing the container.  (So if you need truly private instances, you will need to create separate containers.)

But, if all you need is to give users domain-specific hostnames, or separate sender IP reputation for different domains, you *can* accomplish that with a single shared container.

#### Vanity or Private-Label Logins

Let's say you want to give each domain its own `mail.mydomain.com` address for users to put into their mail clients, log into on the web, use as an MX entry, etc.  You don't need multiple IP addresses to do this, just multiple hostnames.  All that's needed is to:

* Have each vanity/private-label hostname resolve to one of the IP addresses the container listens on (e.g. by being a CNAME of the primary hostname)
* Add each such hostname to the  "Alternative names" of your TLS certificate in the "Mailserver settings" of the primary admin interface

You must, however, still pick *one* primary hostname for the container, as that's what you'll use to boot up the container and access the admin interface to create the TLS certificate.  The primary hostname will be the primary name on that certificate, with the vanity hostnames added as alternative names, once they're resolving correctly via public DNS, and the container is listening on the corresponding IP(s).

#### Separate IPs for Different Domains

If you want to give different domains their own IPs as well as separate hostnames, the steps are the same, except that each private-label hostname would have `A`  or `AAAA` records pointing to the relevant IP address, instead of a CNAME pointing to the primary hostname.  If you want these IPs to be used for outgoing mail as well, you'll also need to configure an `outbound-hosts.yml` file, as described in the next section.  (And if needed, add them to the `SEND_ON` variable.)

You will, of course, still need to configure the container to listen on all these IPs, either by explicitly putting them in `LISTEN_ON`, or by adding them as `A` or `AAAA` records for the primary hostname.  Or, if you're dedicating the entire server to a single poste instance, you can use `LISTEN_ON=*` to listen on every IP the box has.

(Note, however, that since poste.io only supports using a single TLS certificate for all functions, it will still be possible for clients connecting to the container to see all the hostnames it serves, so if that isn't acceptable for your setup, then you will need to create separate instances instead, each serving separate IPs.)

### Managing Sender IPs

In some environments, you may wish to use different sending IP addresses for different origin domains.  To support this use case, you can add a file named `outbound-hosts.yml` to the `/data` volume, laid out like this:

```yaml
# This info will be used for domains that don't have an entry of their own
default:
  helo: poste.mygenericdomain.com
  ip: 1.2.3.4

exampledomain.com:
  helo: mx.exampledomain.com
  ip: 5.6.7.8
```

With the above configuration, mails sent from `exampledomain.com` will be sent with a HELO of `mx.exampledomain.com`, using an outbound IP of `5.6.7.8`, and mail for any other domain will use the defaults.  (Assuming, of course, that `5.6.7.8` is one of the addresses the container listens on.)

Note that the information in this file is *not* validated against DNS or checked for security (aside from a basic check that the IP is included in the expansion of `SEND_ON`).  It is your responsibility to ensure that all `helo` hostnames exist in DNS with the matching `ip` , and that all listed IP addresses are actually valid for the network interfaces on your server.

In addition, for best deliverability, you should also:

* Ensure that SPF will pass for a given domain + `helo`/`ip` combination
* Ensure that the reverse DNS for the given `ip` values has a reasonable result (preferably the same as the `helo`)
* Ensure that each `helo` address used as an MX is listed in the "Alternative names" of your TLS certificate in the "Mailserver settings" of the poste admin interface, and that its corresponding `ip` is an address the container listens on.

And of course, you will need to update all of this information whenever any of the configuration changes!  If you control DNS for all the relevant domains yourself, you may be able to generate this file automatically from your domain list and DNS: e.g. by looking up MX records and their corresponding addresses.  (But you shouldn't trust the DNS for domains you don't control, as that would effectively let your clients pick their own sending IPs.)

### IPv6 Support

This image supports listening on IPv6 addresses, and in principle allows sending mail via them as well.  However, since relatively few mailservers are actually configured to receive mail via IPv6, we don't recommend actually *using* IPv6 addresses for outgoing mail, unless your server will be communicating exclusively with other mailservers that support IPv6.  (You should also test to make sure IPv6 sending actually works correctly in your networking environment, and to see what happens when you try sending outbound IPv6 mail to an IPv4-only server.)

### Using Custom Roundcube Plugins

On startup, this image will automatically install, activate, and attempt to run SQL initialization for any Roundcube plugins found as subdirectories of `/data/roundcube-plugins`.  Only plugins without dependencies (other than those already installed with Roundcube) will work correctly.  (Plugins should generally be installed with world-readable permissions, but *not* owned or writable by the www-data user or group, so that file-writing exploits don't become remote execution exploits.)

If you need to force a re-run of a plugin's setup SQL, you can remove its name from the `/data/roundcube/installed-plugins` file, then restart the container.  You can uninstall a plugin by stopping the container, removing it from the `/data/roundcube-plugins` directory, and then starting the container again.  (Any SQL changes made by the plugin will remain in place.)

This feature is still quite experimental (and has only been tested with one plugin so far), so be sure to experiment with it on a development instance before using it in production.

#### The DES_KEY Variable

Some plugins (such as [ident_switch](https://bitbucket.org/BoresExpress/ident_switch)) may need to store encrypted data in the roundcube database.  By default, poste generates a new encryption key on every container start, rendering such data unable to be decrypted.  To work around this issue, you can set a `DES_KEY` environment variable containing a string of exactly 48 random hex characters.  The given string will be used across restarts, allowing encrypted data stored in a previous session to be decrypted correctly.  You can generate a suitable key using `openssl rand -hex 24` (which will generate 24 random bytes = 48 hex digits).  The string used must be *exactly* 48 hex digits, or else the container's webmail service will silently cease to function.

### Can I use these changes with poste.io's PRO version?

I don't know, but you can find out by cloning this repo, changing the `FROM` in the Dockerfile, and trying to run the resulting build.  It *might* work, since the main difference between the two versions is some admin interface code left out of the free version.  But if that left-out code contains hardcoded or implicit references to localhost or 127.0.0.1, then those admin features will probably break, as they won't have been patched to use unix-domain sockets (or the container's hostname) instead.

If they do break, and you can figure out what to patch (most likely, PHP code in `/opt/admin/src/ProBundle/`), let me know.  (Or if it works fine, I'd love to know that, too!)

### Docker Tags

Apart from `latest`, and `unstable`, current versions of this image on docker hub are tagged as a combination of the upstream version and a version number for this image's additions.  For example, `2.2.2-0.3.1` is the `0.3.1` revision of upstream poste's `2.2.2` tag, if you need to pin a specific revision.  You can also just use the upstream version (e.g. `2.2.2`) to get the latest patches for that upstream version, or `latest` to get the most-recent stable version.  The `unstable` tag always refers to the current `master` branch from github.

