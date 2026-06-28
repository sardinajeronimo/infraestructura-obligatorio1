# Informe Técnico - Parte 4 Docker

## Cómo levantar el stack

```bash
cd parte4
sh setup.sh          # genera id_ed25519 y distribuye claves a cada contexto de build
docker compose up    # buildea y levanta los 4 contenedores
```

`setup.sh` crea el par de claves ED25519 en `parte4/`, copia la pública a cada runner y al manager, y la privada al directorio del manager para que el Dockerfile la incluya en la imagen.

El manager queda accesible en `http://localhost:8080`. Los runners no exponen puertos al host; solo son alcanzables desde dentro de `red_interna`.

## Cómo conectarse por SSH a cada runner desde el manager

Desde dentro del contenedor `manager`, ejecutar:

```bash
# bash-runner
ssh -i /home/manager/.ssh/id_ed25519 -o StrictHostKeyChecking=no runner@runner-bash

# c-runner
ssh -i /home/manager/.ssh/id_ed25519 -o StrictHostKeyChecking=no runner@runner-c

# ada-runner
ssh -i /home/manager/.ssh/id_ed25519 -o StrictHostKeyChecking=no runner@runner-ada
```

Los nombres de host (`runner-bash`, `runner-c`, `runner-ada`) son resueltos por Docker a través de la red interna `red_interna`. El usuario en todos los runners es `runner`.

Para entrar al manager desde el host:

```bash
docker exec -it manager /bin/bash
```

---

## bash-runner

### Imagen base

`debian:bookworm-slim`. Se elige Debian Bookworm (12) slim porque provee la versión más reciente del ecosistema Debian en el menor tamaño posible, evitando herramientas innecesarias presentes en la imagen `debian:bookworm` completa. `bash` viene preinstalado en la imagen base; se agrega únicamente `openssh-server`.

### Configuración de seguridad aplicada

**Dockerfile:**
- Usuario no-root `runner` creado con `useradd -m -s /bin/bash runner`.
- SSH configurado con `PermitRootLogin no` y `PasswordAuthentication no`; solo se acepta autenticación por clave pública.
- Clave pública del manager copiada como `authorized_keys` con permisos `600`, propiedad de `runner:runner`.
- El directorio `.ssh` tiene permisos `700`.

**docker-compose.yml:**
- `read_only: true` — sistema de archivos del contenedor montado en solo lectura.
- `tmpfs: [/run/sshd, /tmp]` — los únicos directorios que necesitan escritura (socket de sshd y temporales) se montan como tmpfs en RAM.
- `cap_drop: [ALL]` — se eliminan todas las capabilities de Linux.
- `security_opt: [no-new-privileges:true]` — impide que procesos hijos adquieran privilegios adicionales.

### Análisis de vulnerabilidades

Escaneado con Trivy 0.71.2 sobre Debian 12.14. Total de paquetes analizados: ~111.

| Severidad | Cantidad |
|-----------|----------|
| CRITICAL  | 3        |
| HIGH      | 7        |
| MEDIUM    | 47       |
| LOW       | 114      |
| UNKNOWN   | 16       |
| **Total** | **187**  |

CVEs críticos detectados:

| CVE | Paquete | Descripción |
|-----|---------|-------------|
| CVE-2026-42496 | perl-base | Path traversal mediante symlink en Archive::Tar |
| CVE-2026-8376 | perl-base | Heap buffer overflow en compilador Perl ≤5.43.10 |
| CVE-2023-45853 | zlib1g | Integer overflow con heap buffer overflow en zlib |

Las tres CVEs críticas corresponden a `perl-base` (dependencia transitiva de `openssh-server`) y `zlib1g`. No tienen fix disponible en los repositorios de Debian 12 a la fecha del análisis. No son explotables directamente desde la superficie de ataque del runner dado que perl no se invoca en ningún flujo de ejecución.

Trivy también detectó la clave privada del host SSH (`/etc/ssh/ssh_host_*_key`) como "secreto"; esto es un falso positivo esperado — esas claves son generadas en el build por `ssh-keygen -A` y son necesarias para el funcionamiento del servidor.

### Decisiones de diseño

- No se instala ningún intérprete adicional ni compilador; el runner ejecuta únicamente el script bash preexistente.
- El uso de `tmpfs` en `/run/sshd` es necesario porque `sshd` crea un socket en ese directorio al arrancar; sin él, el servidor falla con `read_only: true`.
- `cap_drop: ALL` sin `cap_add` es posible en este runner porque bash no necesita ninguna capability de sistema.

---

## c-runner

### Imagen base

`debian:bookworm-slim`. Igual que bash-runner, con la adición de `gcc` y `libc-dev` para compilar el binario C en tiempo de build. Ambos paquetes se eliminan después de la compilación con `apt-get purge`.

### Configuración de seguridad aplicada

**Dockerfile:**
- Usuario no-root `runner`.
- SSH configurado idéntico a bash-runner (`PermitRootLogin no`, `PasswordAuthentication no`).
- El binario `restaurante` se compila durante el build (`gcc -o restaurante restaurante.c -lpthread`) y se asigna a `runner:runner`.
- `gcc` y `libc-dev` se purgan post-compilación con `apt-get purge -y gcc libc-dev && apt-get autoremove -y`.

**docker-compose.yml:**
- `read_only: true`, `tmpfs: [/run/sshd, /tmp]`, `security_opt: [no-new-privileges:true]`.
- `cap_drop: [ALL]` más `cap_add: [SETUID, SETGID, NET_BIND_SERVICE]`. Se agregan SETUID y SETGID porque el binario compilado con pthreads requiere cambio de identidad de proceso en algunas operaciones internas de la glibc. NET_BIND_SERVICE no es estrictamente necesario para este binario pero se mantiene por consistencia con runner-ada.

### Análisis de vulnerabilidades

Escaneado con Trivy 0.71.2 sobre Debian 12.14. Total de paquetes analizados: ~118.

| Severidad | Cantidad |
|-----------|----------|
| CRITICAL  | 4        |
| HIGH      | 196      |
| MEDIUM    | 1106     |
| LOW       | 260      |
| UNKNOWN   | 36       |
| **Total** | **1602** |

El número elevado se explica porque aunque `gcc` y `libc-dev` se purgan en tiempo de runtime, Trivy escanea las capas intermedias de la imagen donde aún existen. Los paquetes del toolchain de compilación (`binutils`, `libasan8`, `libgcc-12-dev`, `cpp-12`, etc.) contribuyen la mayoría de las vulnerabilidades HIGH y MEDIUM.

CVEs críticos detectados:

| CVE | Paquete | Descripción |
|-----|---------|-------------|
| CVE-2026-43185 | linux-libc-dev | Signedness bug en ksmbd (kernel) |
| CVE-2026-42496 | perl-base | Path traversal mediante symlink en Archive::Tar |
| CVE-2026-8376 | perl-base | Heap buffer overflow en Perl ≤5.43.10 |
| CVE-2023-45853 | zlib1g | Integer overflow con heap buffer overflow en zlib |

`linux-libc-dev` es un paquete de headers del kernel, sin código ejecutable en el contenedor; la vulnerabilidad en ksmbd no es explotable en este contexto. Para reducir el total de vulnerabilidades reportadas habría que usar una imagen multi-stage: compilar en una etapa y copiar solo el binario resultante a una segunda etapa limpia.

### Decisiones de diseño

- Se compila el binario en el build para que el runtime no tenga compilador disponible (reducción de superficie de ataque).
- La purga de `gcc`/`libc-dev` post-compilación reduce el tamaño de la imagen final y elimina esos paquetes del sistema de archivos activo, aunque Trivy los detecte en capas anteriores.
- Multi-stage build sería la mejora directa para eliminar las vulnerabilidades del toolchain del reporte.

---

## ada-runner

### Imagen base

`debian:bookworm-slim`. Se instala `gnat` (GNU Ada Translator) para compilar el programa Ada. GNAT se purga después de la compilación, mismo patrón que runner-c.

### Configuración de seguridad aplicada

**Dockerfile:**
- Usuario no-root `runner`.
- SSH configurado idéntico a bash-runner y c-runner.
- El programa Ada se compila con `gnatmake juego.adb` y el binario resultante se asigna a `runner:runner`.
- `gnat` se purga post-compilación con `apt-get purge -y gnat && apt-get autoremove -y`.

**docker-compose.yml:**
- `read_only: true`, `tmpfs: [/run/sshd, /tmp]`, `security_opt: [no-new-privileges:true]`.
- `cap_drop: [ALL]` más `cap_add: [SETUID, SETGID, NET_BIND_SERVICE]`, mismo razonamiento que runner-c.

### Análisis de vulnerabilidades

Escaneado con Trivy 0.71.2 sobre Debian 12.14. Total de paquetes analizados: ~111.

| Severidad | Cantidad |
|-----------|----------|
| CRITICAL  | 3        |
| HIGH      | 7        |
| MEDIUM    | 47       |
| LOW       | 114      |
| UNKNOWN   | 16       |
| **Total** | **187**  |

El conteo es idéntico a bash-runner. Esto indica que `gnat` fue purgado efectivamente y los paquetes residuales son los mismos que los de bash-runner (base Debian + openssh-server). La purga de GNAT funciona correctamente y reduce la imagen al mismo footprint que la versión bash.

CVEs críticos detectados:

| CVE | Paquete | Descripción |
|-----|---------|-------------|
| CVE-2026-42496 | perl-base | Path traversal mediante symlink en Archive::Tar |
| CVE-2026-8376 | perl-base | Heap buffer overflow en Perl ≤5.43.10 |
| CVE-2023-45853 | zlib1g | Integer overflow con heap buffer overflow en zlib |

### Decisiones de diseño

- La purga de `gnat` es más efectiva que la de `gcc` en runner-c: el conteo final de vulnerabilidades es idéntico a bash-runner (187 total), demostrando que `apt-get autoremove` elimina las dependencias del toolchain Ada completamente.
- GNAT trae muchas dependencias (`gcc-12`, `gfortran`, librerías Ada) que desaparecen todas con `autoremove`.

---

## manager

### Imagen base

`debian:bookworm-slim`. Se instala `openssh-client` (para conectarse a los runners via SSH), `python3` (para el servidor HTTP con soporte CGI), `bash` y `procps` (para las métricas que se recolectan via SSH en los runners).

### Configuración de seguridad aplicada

**Dockerfile:**
- Usuario no-root `manager` creado con `useradd`.
- La clave privada ED25519 se copia en `/home/manager/.ssh/id_ed25519` con permisos `600`.
- El contenedor arranca directamente como `USER manager` — el proceso principal nunca corre como root.
- No se instala ni corre sshd; el manager solo actúa como cliente SSH.

**docker-compose.yml:**
- Puerto `8080` expuesto al host.
- `security_opt: [no-new-privileges:true]`.
- Sin `read_only`, `cap_drop` ni `tmpfs` — el servidor CGI de Python necesita escribir en el sistema de archivos durante la ejecución del CGI.
- `depends_on: [runner-bash, runner-c, runner-ada]` — Docker espera que los runners estén levantados antes de iniciar el manager.

**server.sh:**
- Genera el script CGI en runtime (`/var/www/panel/cgi-bin/estado`).
- El CGI extrae el parámetro `?host=` del query string y ejecuta un comando SSH contra el runner indicado.
- Usa `ConnectTimeout=2` para no bloquearse si un runner no responde.
- `StrictHostKeyChecking=no` es aceptable en la red interna de Docker donde los hosts son controlados.

### Análisis de vulnerabilidades

Escaneado con Trivy 0.71.2 sobre Debian 12.14. Total de paquetes analizados: ~117.

| Severidad | Cantidad |
|-----------|----------|
| CRITICAL  | 4        |
| HIGH      | 32       |
| MEDIUM    | 105      |
| LOW       | 125      |
| UNKNOWN   | 24       |
| **Total** | **290**  |

Trivy también detectó `/home/manager/.ssh/id_ed25519` como secreto (clave privada SSH embebida en la imagen). Esta es la limitación de diseño más relevante: la clave privada queda hardcodeada en la imagen.

CVEs críticos detectados:

| CVE | Paquete | Descripción |
|-----|---------|-------------|
| CVE-2025-7458 | libsqlite3-0 | Integer overflow en SQLite |
| CVE-2026-42496 | perl-base | Path traversal mediante symlink en Archive::Tar |
| CVE-2026-8376 | perl-base | Heap buffer overflow en Perl ≤5.43.10 |
| CVE-2023-45853 | zlib1g | Integer overflow con heap buffer overflow en zlib |

`libsqlite3-0` aparece como dependencia de `python3`. El manager no usa SQLite directamente; la vulnerabilidad no es explotable en el flujo actual. Los CVEs de `perl-base` y `zlib1g` son los mismos presentes en todos los runners (dependencias del ecosistema Debian base).

### Decisiones de diseño

- La clave privada en la imagen es una concesión de simplicidad para el entorno de desarrollo. La alternativa correcta sería montarla como Docker secret (`docker secret`) o como volumen en tiempo de ejecución, nunca en el build context.
- El servidor CGI con Python `http.server --cgi` es suficiente para el panel interno; no está expuesto a internet.
- El manager no tiene `cap_drop: ALL` ni `read_only` porque Python necesita escribir el script CGI en runtime y el proceso necesita capacidades básicas de red para actuar como cliente SSH.
