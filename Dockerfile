FROM analogic/poste.io:2.2.2
RUN apt-get update && apt-get install less  # 'less' is Useful for debugging
COPY files /
RUN /patches && rm /patches