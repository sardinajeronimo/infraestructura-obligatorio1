#Informe Autopsia 

##Ticket 104
Linea del fallo (linea 18):
grep $PARAMETRO $ARCHIVO_CSV
Error: Bash aplica word splitting sobre $PARAMETRO, dividiendo por espacios. grep toma la primera palabra como patrón y el resto como
 nombres de archivos, por lo que nunca encuentra el objeto pasado como parámetro.
Fix: grep "$PARAMETRO" "$ARCHIVO_CSV", generando que se guarde todo como el parametro y se busque correctamente en el archivo. 


##Ticket 105
Linea del fallo (linea 23):
rm $DIR_MERCADERIA/$PARAMETRO*.txt
Error: Cuando Parametro esta vacio, Bash aplica globbing, expandiendo la línea a rm ./mercaderia/*.txt, generando que se elimine toda mercaderia de los archivos txt.
Fix: Validar que $PARAMETRO no este vacio antes de ejecutar el comando rm y tambien citar la variable correctamente con if [ -z "$PARAMETRO" ]; then
    echo "Error: debes indicar el nombre de la escuderia."
    exit 1
fi
rm "$DIR_MERCADERIA/${PARAMETRO}"*.txt
