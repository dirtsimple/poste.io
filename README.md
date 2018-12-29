## A Fully-Isolated Poste.io Image

[poste.io](https://poste.io) is a pretty cool email server implementation for docker.  Unfortunately, it doesn't play well with other mail servers on the same machine, which makes it hard to e.g., have both a development and production instance.

Specifically, poste.io *requires* docker host mode networking, but then binds its outward-facing services to *every* IP address of the machine, *and* binds several of its internal services to localhost ports (24, 6379, 11332-11334, 11380, and 13001), which can conflict with things besides mail servers or other poste.io instances.

As a result, poste.io not only doesn't play well with other mail servers, it doesn't play well with being used on a server that *does anything else*.  (It almost might as well not be a docker container at all!)

So this image fixes these issues, by tweaking service configurations to only bind services on the IP that corresponds to the container's hostname, and replace localhost TCP sockets with unix domain sockets, kept privately within the container.  (Thereby preventing conflicts or confusion with other bindings of those ports on the localhost interface.)

Unfortunately, poste's admin tool isn't written with unix sockets in mind, and neither are significant parts of haraka and its plugins.  Thus, in addition to adding the configuration files found under [files/](files/), this image also has to [patch a lot of files](files/patches).  (Most of the patching is done at image build time, but a few are tweaked at container start by a patched version of `/etc/cont-init.d/23-nginx.sh`, because nginx and haraka don't allow variable substitution in the part of their config files that set listening ports.)

(Note: this image relies even more on a correct docker hostname than poste.io does.  Make sure that the hostname you assign to the container is public, fully-qualified, and maps to exactly one IPv4 address.)