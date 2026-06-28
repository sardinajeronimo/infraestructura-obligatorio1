#!/bin/sh
# Genera el par de claves SSH para el manager si no existen.
# Correr una sola vez antes de: docker compose up

KEY="id_ed25519"

if [ -f "$KEY" ]; then
  echo "Clave $KEY ya existe, no se genera de nuevo."
else
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "manager@docker"
  echo "Claves generadas: $KEY y $KEY.pub"
fi

# Copia la clave pública a cada runner y al manager
cp "$KEY.pub" manager/id_ed25519.pub
cp "$KEY.pub" runner-bash/id_ed25519.pub
cp "$KEY.pub" runner-c/id_ed25519.pub
cp "$KEY.pub" runner-ada/id_ed25519.pub

# Copia la clave privada al manager (para que el Dockerfile la encuentre)
cp "$KEY" manager/id_ed25519

echo "Listo. Ahora corré: docker compose up"
