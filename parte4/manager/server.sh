#!/bin/sh
# Creamos el directorio CGI
mkdir -p /var/www/panel/cgi-bin

# Script CGI que responde con métricas del runner solicitado
cat > /var/www/panel/cgi-bin/estado << 'CGISCRIPT'
#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

# Extraemos el parámetro ?host= de la query string
HOST=$(echo "$QUERY_STRING" | sed 's/host=//')

# Intentamos conectar por SSH y obtener métricas básicas
# -o StrictHostKeyChecking=no: no pide confirmación de host (red interna de confianza)
# -o ConnectTimeout=2: si no responde en 2s, lo marcamos inactivo
RESULTADO=$(ssh -i /home/manager/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=2 \
    runner@$HOST \
    "cpu=\$(top -bn1 | grep '%Cpu' | awk '{print \$2}')%; \
     mem=\$(free -m 2>/dev/null | awk '/Mem/{printf \"%dMB/%dMB\", \$3, \$2}' 2>/dev/null || echo 'N/D'); \
     echo \"{\\\"cpu\\\":\\\"\$cpu\\\",\\\"mem\\\":\\\"\$mem\\\"}\"" 2>/dev/null)

if [ -n "$RESULTADO" ]; then
    echo "$RESULTADO"
else
    echo "null"
fi
CGISCRIPT

chmod +x /var/www/panel/cgi-bin/estado

# Arrancamos el servidor con soporte CGI habilitado
cd /var/www/panel && python3 -m http.server --cgi 8080