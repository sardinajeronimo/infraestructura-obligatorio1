# Stage 1: compilar
FROM debian:bookworm-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libc-dev && \
    rm -rf /var/lib/apt/lists/*

COPY app/restaurante.c /build/restaurante.c
RUN gcc -o /build/restaurante /build/restaurante.c -lpthread

# Stage 2: imagen final sin toolchain
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-server && \
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

COPY --from=builder /build/restaurante /home/runner/app/restaurante
RUN chown runner:runner /home/runner/app/restaurante

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
