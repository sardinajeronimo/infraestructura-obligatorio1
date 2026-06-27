FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends gnat openssh-server && \
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
RUN cd /home/runner/app && gnatmake juego.adb && chown runner:runner juego

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]