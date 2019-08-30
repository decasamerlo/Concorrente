#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

#define N_PIDS 2

//       (pai)
//         |
//    +----+----+
//    |         |
// filho_1   filho_2


// ~~~ printfs  ~~~
// pai (ao criar filho): "Processo pai criou %d\n"
//    pai (ao terminar): "Processo pai finalizado!\n"
//  filhos (ao iniciar): "Processo filho %d criado\n"

// Obs:
// - pai deve esperar pelos filhos antes de terminar!

int main(int argc, char** argv) {
    int status;
    pid_t pid_filhos[N_PIDS];

    for (int i = 0; i < N_PIDS; i++) {
      fflush(stdin);
      pid_filhos[i] = fork();
      if (pid_filhos[i]) {
        printf("Processo pai criou %d\n", pid_filhos[i]);
      } else {
        printf("Processo filho %d criado\n", getpid());
        exit(1);
      }
    }

    wait(&status);
    printf("Processo pai finalizado!\n");
    return 0;
}
