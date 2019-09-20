#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>
#include <time.h>
#include <semaphore.h>

int produzir(int value);    //< definida em helper.c
void consumir(int produto); //< definida em helper.c
void *produtor_func(void *arg);
void *consumidor_func(void *arg);

int indice_produtor, indice_consumidor, tamanho_buffer;
int* buffer;

sem_t semaforo_produtor, semaforo_consumidor;
pthread_mutex_t consumidor_mtx, produtor_mtx;

//Você deve fazer as alterações necessárias nesta função e na função
//consumidor_func para que usem semáforos para coordenar a produção
//e consumo de elementos do buffer.
void *produtor_func(void *arg) {
    //arg contem o número de itens a serem produzidos
    int max = *((int*)arg);
    for (int i = 0; i < max; ++i) {
        int produto = produzir(i); //produz um elemento normal
        sem_wait(&semaforo_produtor);
        pthread_mutex_lock(&produtor_mtx); //seção crítica entre produtores
        indice_produtor = (indice_produtor + 1) % tamanho_buffer; //calcula posição próximo elemento
        buffer[indice_produtor] = produto; //adiciona o elemento produzido à lista
        pthread_mutex_unlock(&produtor_mtx);
        sem_post(&semaforo_consumidor);
    }
    return NULL;
}

void *consumidor_func(void *arg) {
    while (1) {
        sem_wait(&semaforo_consumidor);
        pthread_mutex_lock(&consumidor_mtx); // Seção crítica entre consumidores
        indice_consumidor = (indice_consumidor + 1) % tamanho_buffer; //Calcula o próximo item a consumir
        int produto = buffer[indice_consumidor]; //obtém o item da lista
        pthread_mutex_unlock(&consumidor_mtx);
        sem_post(&semaforo_produtor);
        //Podemos receber um produto normal ou um produto especial
        if (produto >= 0)
            consumir(produto); //Consome o item obtido.
        else
            break; //produto < 0 é um sinal de que o consumidor deve parar
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc < 5) {
        printf("Uso: %s tamanho_buffer itens_produzidos n_produtores n_consumidores \n", argv[0]);
        return 0;
    }

    tamanho_buffer = atoi(argv[1]);
    int itens = atoi(argv[2]);
    int n_produtores = atoi(argv[3]);
    int n_consumidores = atoi(argv[4]);
    printf("itens=%d, n_produtores=%d, n_consumidores=%d\n",
	   itens, n_produtores, n_consumidores);

    pthread_t produtores[n_produtores], consumidores[n_consumidores];

    //Iniciando buffer
    indice_produtor = 0;
    indice_consumidor = 0;
    buffer = malloc(sizeof(int) * tamanho_buffer);

    // Crie threads e o que mais for necessário para que n_produtores
    // threads criem cada uma n_itens produtos e o n_consumidores os
    // consumam.

    pthread_mutex_init(&produtor_mtx, NULL);
    pthread_mutex_init(&consumidor_mtx, NULL);
    sem_init(&semaforo_produtor, 0, tamanho_buffer);
    sem_init(&semaforo_consumidor, 0, 0);

    for(int i=0; i < n_produtores; i++) {
        pthread_create(&produtores[i], NULL, produtor_func, &itens);
    }

    for(int i=0; i < n_consumidores; i++) {
        pthread_create(&consumidores[i], NULL, consumidor_func, NULL);
    }

    for(int i=0; i < n_produtores; i++) {
        pthread_join(produtores[i], NULL);
    }

    for (int i = 0; i < n_consumidores; ++i) {
        sem_wait(&semaforo_produtor);
        buffer[indice_produtor = (indice_produtor+1) % tamanho_buffer] = -1;
        sem_post(&semaforo_consumidor);
    }

    for(int i=0; i < n_consumidores; i++) {
        pthread_join(consumidores[i], NULL);
    }
    
    pthread_mutex_destroy(&produtor_mtx);
    pthread_mutex_destroy(&consumidor_mtx);
    sem_destroy(&semaforo_produtor);
    sem_destroy(&semaforo_consumidor);
    
    //Libera memória do buffer
    free(buffer);

    return 0;
}

