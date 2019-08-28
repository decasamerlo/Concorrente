#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#include <semaphore.h>
#include <time.h>

sem_t* garfos;
int n_filosofos;
int comida_por_prato;

void comer(int id, int* comida, int garfo_esq, int garfo_dir) {
    sem_wait(&garfos[garfo_esq]);
    sem_wait(&garfos[garfo_dir]);
    
    --*comida;
    
    sem_post(&garfos[garfo_esq]);
    sem_post(&garfos[garfo_dir]);
}

void* filosofo(void* arg) {
    int prato = comida_por_prato;
    int id = *(int*)arg;
    int garfo_esq = id;
    int garfo_dir = (id+1)%n_filosofos;

    while (prato) 
        comer(id, &prato, garfo_esq, garfo_dir);
    
    printf("FIL %d: tchau\n", id); // acabou a comida
    return NULL;
}


int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Uso: %s n_filosofos comida_por_prato\n", argv[0]);
        return 1;
    }

    n_filosofos = atoi(argv[1]);
    comida_por_prato = atoi(argv[2]);

    pthread_t* filosofos = (pthread_t*)malloc(sizeof(pthread_t)*n_filosofos);
    int* ids = (int*)malloc(sizeof(int)*n_filosofos);
    garfos = (sem_t*)malloc(sizeof(sem_t)*n_filosofos);
    for (int i = 0; i < n_filosofos; ++i) sem_init(garfos+i, 0, 1);
    for (int i = 0; i < n_filosofos; ++i) {
        ids[i] = i;
        pthread_create(filosofos+i, NULL, filosofo, ids+i);
    }

    for (int i = 0; i < n_filosofos; ++i) pthread_join(filosofos[i], NULL);
    for (int i = 0; i < n_filosofos; ++i) sem_destroy(garfos+i);
    
    free(filosofos);
    free(ids);
    free(garfos);
}
