FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-client bash python3 procps && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash manager

RUN mkdir -p /home/manager/.ssh && chmod 700 /home/manager/.ssh
COPY id_ed25519 /home/manager/.ssh/id_ed25519
COPY id_ed25519.pub /home/manager/.ssh/id_ed25519.pub
RUN chown -R manager:manager /home/manager/.ssh && \
    chmod 600 /home/manager/.ssh/id_ed25519

COPY panel/ /var/www/panel/
RUN chown -R manager:manager /var/www/panel
COPY server.sh /home/manager/server.sh
RUN chmod +x /home/manager/server.sh

EXPOSE 8080
USER manager
CMD ["/bin/sh", "/home/manager/server.sh"]