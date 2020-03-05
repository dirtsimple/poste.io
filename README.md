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
* By default, outgoing email to other mail servers will be sent via the first IP address returned by running `hostname -i` in the container.  If you need to override this, configure the container with an `OUTBOUND_MAIL_IP` environment variable specifying the IP address to be used.