## A Fully-Isolated Poste.io Image

[poste.io](https://poste.io) is a pretty cool email server implementation for docker.  Unfortunately, when used with host-mode networking (the poste.io recommended configuration) it doesn't play well with other mail servers on the same machine.  (Which makes it hard to e.g., have both a development and production instance.)

Specifically, in host mode networking, poste.io binds its outward-facing services to *every* IP address of the machine, *and* binds several of its internal services to localhost ports (6379, 11332-11334, 11380, 11381, and 13001), which can conflict with things besides mail servers or other poste.io instances.

As a result, poste.io not only doesn't play well with other mail servers, it doesn't play well with being used on a server that *does anything else*.  (It almost might as well not be a docker container at all!)

So this image fixes these issues, by tweaking service configurations to only bind services on the IPs that correspond to the container's hostname, and replace localhost TCP sockets with unix domain sockets, kept privately within the container.  (Thereby preventing conflicts or confusion with other bindings of those ports on the localhost interface.)

Unfortunately, poste's admin tool isn't written with unix sockets in mind, and neither are significant parts of haraka and its plugins.  Thus, in addition to adding the configuration files found under [files/](files/), this image also has to [patch a lot of files](files/patches).  (Most of the patching is done at image build time, but a few are tweaked at container start by an [init script](files/etc/cont-init.d/25-bind-hostname.sh), because nginx and haraka don't allow variable substitution in the part of their config files that set listening ports.)

### Usage

To use this image, just replace `analogic/poste.io` in your config with `dirtsimple/poste.io`.  But take careful note of the following:

* You **must** configure the container with a fully-qualified hostname, whose IP address(es) **must** be listed in the public DNS system
* The IP address(es) must be public IPs, and *should* have reverse DNS pointing to the container's hostname
* You should be using **host-mode networking**, since in any other networking mode, the original `analogic/poste.io` image is sufficiently isolated without these patches!
* By default, outgoing email to other mail servers will be sent via the first IP address returned by running `hostname -i` in the container.  If you need to override this, configure the container with an `OUTBOUND_MAIL_IP` environment variable specifying the IP address to be used, or create a `/data/outbound-hosts.yml` file as described below, with an appropriate `default` entry.

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

With the above configuration, mails sent from `exampledomain.com` will be sent with a HELO of `mx.exampledomain.com`, using an outbound IP of `5.6.7.8`, and mail for any other domain will use the defaults.

Note that the information in this file is *not* validated against DNS or checked for security.  It is your responsibility to ensure that all `helo` hostnames exist in DNS with the matching `ip` , and that all listed IP addresses are actually valid for the network interfaces on your server.  In addition, for best deliverability, you should also:

* Ensure that SPF will pass for a given domain + `helo`/`ip` combination
* Ensure that the reverse DNS for the given `ip` values has a reasonable result (preferably the same as the `helo`)
* Ensure that each `helo` address used as an MX is listed in the "Alternative names" of your TLS certificate in the "Mailserver settings" of the poste admin interface, and that its corresponding `ip` is listed in an `A` or `AAAA` record for the *container's* hostname.  (So that the container will listen for incoming mail on that address, and respond with a valid certificate.)  This step is not necessary for domains that simply use the container's hostname as their MX.

And of course, you will need to update all of this information whenever any of the configuration changes.  If you control DNS for all the relevant domains yourself, you may be able to generate this file automatically from your domain list and DNS: e.g. by looking up MX records and their corresponding addresses.  (But you shouldn't trust the DNS for domains you don't control, as that would let your clients pick their own sending IPs!)

### Docker-Compose Example

Here's a trivial `docker-compose.yml` setup for using this image:

```yaml
version: "2.3"
services:
  poste:
    image: dirtsimple/poste.io
    restart: always
    network_mode: host

    # to serve everything on `mail.example.com`:
    hostname: mail
    domainname: example.com

    volumes:
      - ./data:/data
      - /etc/localtime:/etc/localtime:ro
```

This example assumes that `mail.example.com` is mapped in the public DNS to one or more IP addresses on the server where the container runs, and that *none* of those IP addresses have any other services listening on ports 25, 80, 110, 143, 443, 466, 587, 993, 995, or 4190.  (You should, of course, replace `mail` and `example.com` with appropriate values for your installation.)