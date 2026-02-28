ARG UPSTREAM=2.3.10
FROM analogic/poste.io:$UPSTREAM
RUN sed -ie s/deb.debian.org/archive.debian.org/ /etc/apt/sources.list && rm /etc/apt/sources.list.d/rspamd.list
RUN apt-get update && apt-get install less  # 'less' is Useful for debugging

# Default to listening only on IPs bound to the container hostname
ENV LISTEN_ON=host
ENV SEND_ON=

COPY files /
RUN /patches && rm /patches
