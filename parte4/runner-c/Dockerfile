FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libc-dev openssh-server && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash runner

RUN ssh-keygen -A && \
    mkdir -p /run/sshd && \
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

RUN mkdir -p /home/runner/.ssh && chmod 700 /home/runner/.ssh
COPY id_ed25519.pub /home/runner/.ssh/authorized_keys
RUN chown -R runner:runner /home/runner/.ssh && \
    chmod 600 /home/runner/.ssh/authorized_keys

COPY app/ /home/runner/app/
RUN cd /home/runner/app && \
    gcc -o restaurante restaurante.c -lpthread && \
    chown runner:runner restaurante

# Borramos gcc después de compilar
RUN apt-get purge -y gcc libc-dev && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]