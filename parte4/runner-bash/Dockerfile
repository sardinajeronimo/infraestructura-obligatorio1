FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends bash openssh-server && \
    rm -rf /var/lib/apt/lists/*

# Creamos usuario no-root
RUN useradd -m -s /bin/bash runner

# Configuramos SSH seguro
RUN ssh-keygen -A && \
    mkdir -p /run/sshd && \
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

# Copiamos la clave pública del manager
RUN mkdir -p /home/runner/.ssh && chmod 700 /home/runner/.ssh
COPY id_ed25519.pub /home/runner/.ssh/authorized_keys
RUN chown -R runner:runner /home/runner/.ssh && \
    chmod 600 /home/runner/.ssh/authorized_keys

# Copiamos la app
COPY app/ /home/runner/app/
RUN chmod +x /home/runner/app/paddock_manager_fixed.sh

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]