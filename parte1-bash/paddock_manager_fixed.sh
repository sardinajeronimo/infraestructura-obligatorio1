#!/bin/bash
# paddock_manager.sh - V1.0 (Legacy)
# Uso: ./paddock_manager.sh [accion] [parametros...]

ACCION=$1
PARAMETRO=$2
ARCHIVO_CSV="inventario_f1.csv"
DIR_MERCADERIA="./mercaderia"

if [ -z "$ACCION" ]; then
    echo "Error: Debes especificar una accion (ingresar, buscar, vender, descatalogar)."
    exit 1
fi

case "$ACCION" in
    buscar)
        echo "Buscando '$PARAMETRO' en el inventario..."
        grep  "$PARAMETRO" "$ARCHIVO_CSV"
        ;;
    
    descatalogar)
        echo "Descatalogando productos y manifiestos de la escuderia: $PARAMETRO"

	if [ -z "$PARAMETRO" ]; then
		echo "Error: debes indicar el nombre de la escuderia"
		exit 1
	fi
        rm "$DIR_MERCADERIA/${PARAMETRO}"*.txt
        # Borrado del CSV
        sed -i "/$PARAMETRO/d" "$ARCHIVO_CSV"
        echo "Operacion finalizada."
        ;;
    
    ingresar)
        echo "Ingresando nuevo producto..."
        echo  "$PARAMETRO" >> "$ARCHIVO_CSV"
        echo "Producto ingresado."
        ;;
    
    vender)
        echo "Vendiendo 1 unidad del ID: $PARAMETRO"
        echo "Función en mantenimiento..."
        ;;
    
    *)
        echo "Acción no reconocida."
        exit 1
        ;;
esac
