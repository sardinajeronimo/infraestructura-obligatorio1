#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <semaphore.h>
#include <unistd.h>
#include <time.h>

#define CANT_COCINEROS    5
#define CANT_MOZOS        10
#define CAPACIDAD_BARRA   8
#define TOTAL_PLATOS      50

int platos_en_barra   = 0;
int platos_preparados = 0;
int platos_entregados = 0;

sem_t vacios;
sem_t llenos;
sem_t mutex_barra;

void *cocinero(void *arg) {
    int id = *(int *)arg;
    unsigned int seed = (unsigned int)(time(NULL)) ^ (unsigned int)(id * 7919);

    while (1) {
        /* Reservar el cupo antes de cocinar: si se chequea despues, los 5
         * cocineros pueden pasar el if con el contador en 48 y sobreproducir. */
        sem_wait(&mutex_barra);
        if (platos_preparados >= TOTAL_PLATOS) {
            sem_post(&mutex_barra);
            break;
        }
        platos_preparados++;
        sem_post(&mutex_barra);

        int tiempo_prep = rand_r(&seed) % 3 + 1;
        sleep(tiempo_prep);
        printf("Cocinero %d preparo un plato\n", id);

        sem_wait(&vacios);

        sem_wait(&mutex_barra);
        platos_en_barra++;
        printf("Cocinero %d dejo un plato en la barra (platos en barra: %d)\n",
               id, platos_en_barra);
        sem_post(&mutex_barra);

        sem_post(&llenos);
    }

    return NULL;
}

void *mozo(void *arg) {
    int id = *(int *)arg;
    unsigned int seed = (unsigned int)(time(NULL)) ^ (unsigned int)((id + 100) * 7919);

    while (1) {
        sem_wait(&mutex_barra);
        if (platos_entregados >= TOTAL_PLATOS) {
            sem_post(&mutex_barra);
            break;
        }
        sem_post(&mutex_barra);

        sem_wait(&llenos);

        sem_wait(&mutex_barra);
        /* Segundo chequeo TOCTOU: otro mozo pudo haber entregado el plato 50
         * mientras este estaba bloqueado en P(llenos). El sem_post(&llenos)
         * propaga la senal de fin a otro mozo bloqueado y evita deadlock. */
        if (platos_entregados >= TOTAL_PLATOS) {
            sem_post(&mutex_barra);
            sem_post(&llenos);
            break;
        }

        platos_en_barra--;
        platos_entregados++;
        printf("Mozo %d retiro un plato de la barra (platos en barra: %d)\n",
               id, platos_en_barra);

        sem_post(&mutex_barra);

        sem_post(&vacios);

        printf("Mozo %d esta entregando el plato\n", id);
        int tiempo_entrega = rand_r(&seed) % 2 + 1;
        sleep(tiempo_entrega);
    }

    return NULL;
}

int main(void) {
    sem_init(&vacios,      0, CAPACIDAD_BARRA);
    sem_init(&llenos,      0, 0);
    sem_init(&mutex_barra, 0, 1);

    pthread_t hilos_cocineros[CANT_COCINEROS];
    pthread_t hilos_mozos[CANT_MOZOS];
    int ids_cocineros[CANT_COCINEROS];
    int ids_mozos[CANT_MOZOS];

    for (int i = 0; i < CANT_COCINEROS; i++) {
        ids_cocineros[i] = i + 1;
        pthread_create(&hilos_cocineros[i], NULL, cocinero, &ids_cocineros[i]);
    }

    for (int i = 0; i < CANT_MOZOS; i++) {
        ids_mozos[i] = i + 1;
        pthread_create(&hilos_mozos[i], NULL, mozo, &ids_mozos[i]);
    }

    for (int i = 0; i < CANT_COCINEROS; i++) {
        pthread_join(hilos_cocineros[i], NULL);
    }

    /* Posts envenenados: destrabar a mozos que quedaron en P(llenos) despues
     * de que los cocineros terminaron. Cada uno hara el segundo chequeo y saldra. */
    for (int i = 0; i < CANT_MOZOS; i++) {
        sem_post(&llenos);
    }

    for (int i = 0; i < CANT_MOZOS; i++) {
        pthread_join(hilos_mozos[i], NULL);
    }

    sem_destroy(&vacios);
    sem_destroy(&llenos);
    sem_destroy(&mutex_barra);

    printf("\n=== Servicio finalizado: %d platos preparados, %d entregados ===\n",
           platos_preparados, platos_entregados);

    return 0;
}
