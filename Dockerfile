FROM analogic/poste.io:2.2.2
RUN apt-get update && apt-get install less  # 'less' is Useful for debugging

# Default to listening only on IPs bound to the container hostname
ENV LISTEN_ON=host
ENV OUTBOUND_MAIL_IP=

COPY files /
RUN /patches && rm /patches
