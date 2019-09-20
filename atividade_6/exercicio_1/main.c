#include <stdio.h>
#include <semaphore.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sys/time.h>

#define WORKER_LOOPS 20

void *worker1_func(void *arg);
void *worker2_func(void *arg);
extern int operacao_worker1();
extern int operacao_worker2();
extern void imprime_resultado(int total, int* lista, int tam_lista);

int total_computado;
int *lista_de_operacoes;
int proximo_indice;

pthread_mutex_t mutex_total;//, mutex_operacao;
sem_t sem_lista;

void *worker1_func(void *arg) {
    for (int i = 0; i < WORKER_LOOPS; ++i) {
        pthread_mutex_lock(&mutex_total);
        printf("Worker 1 obteve mutex_total\n");
        //pthread_mutex_lock(&mutex_operacao);
        int operacao = operacao_worker1();
        //pthread_mutex_unlock(&mutex_operacao);

        total_computado += operacao;
        pthread_mutex_unlock(&mutex_total);
        printf("Worker 1 liberou mutex_total\n");

        sem_wait(&sem_lista);
        printf("Worker 1 obteve sem_lista\n");
        lista_de_operacoes[proximo_indice++] = operacao;
        sem_post(&sem_lista);
        printf("Worker 1 liberou sem_lista\n");
    }
   
    return NULL;
}

void *worker2_func(void *arg) {
    for (int i = 0; i < WORKER_LOOPS; ++i) {
        pthread_mutex_lock(&mutex_total);
        printf("Worker 2 obteve mutex_total\n");
        //pthread_mutex_lock(&mutex_operacao);
        int operacao = operacao_worker2();
        //pthread_mutex_unlock(&mutex_operacao);

        total_computado += operacao;
        pthread_mutex_unlock(&mutex_total);
        printf("Worker 2 liberou mutex_total\n");

        sem_wait(&sem_lista);
        printf("Worker 2 obteve sem_lista\n");
        lista_de_operacoes[proximo_indice++] = operacao;
        sem_post(&sem_lista);
        printf("Worker 2 liberou sem_lista\n");
    }
    return NULL;
}


int main(int argc, char *argv[]) {
    struct timeval begin, end;
    gettimeofday(&begin, NULL);
    //Inicia as variáveis globais
    proximo_indice = 0;
    lista_de_operacoes = malloc(sizeof(int) * 2*WORKER_LOOPS);
    total_computado = 0;

    //Inicia semáforos e mutexes
    sem_init(&sem_lista, 0, 1);
    pthread_mutex_init(&mutex_total, NULL);
    //pthread_mutex_init(&mutex_operacao, NULL);

    //Cria as threads do worker1 e worker2.
    pthread_t worker1, worker2;
    pthread_create(&worker1, NULL, worker1_func, NULL);
    pthread_create(&worker2, NULL, worker2_func, NULL);

    //Join nas threads
    pthread_join(worker1, NULL);
    pthread_join(worker2, NULL);

    imprime_resultado(total_computado, lista_de_operacoes, 2*WORKER_LOOPS);

    //Libera mutexes, semáforos e memória alocada
    sem_destroy(&sem_lista);
    pthread_mutex_destroy(&mutex_total);
    //pthread_mutex_destroy(&mutex_operacao);
    free(lista_de_operacoes);

    gettimeofday(&end, NULL);
    double elapsed = (end.tv_sec - begin.tv_sec) +
    ((end.tv_usec - begin.tv_usec)/1000000.0);
    printf("time = %f\n", elapsed);
    return 0;
}
