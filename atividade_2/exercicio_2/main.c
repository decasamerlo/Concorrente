#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

#define N_FILHOS 2
#define N_NETOS 3

//                          (principal)
//                               |
//              +----------------+--------------+
//              |                               |
//           filho_1                         filho_2
//              |                               |
//    +---------+-----------+          +--------+--------+
//    |         |           |          |        |        |
// neto_1_1  neto_1_2  neto_1_3     neto_2_1 neto_2_2 neto_2_3

// ~~~ printfs  ~~~
//      principal (ao finalizar): "Processo principal %d finalizado\n"
// filhos e netos (ao finalizar): "Processo %d finalizado\n"
//    filhos e netos (ao inciar): "Processo %d, filho de %d\n"

// Obs:
// - netos devem esperar 5 segundos antes de imprmir a mensagem de finalizado (e terminar)
// - pais devem esperar pelos seu descendentes diretos antes de terminar

int main(int argc, char** argv) {
  int status;

  pid_t pid_filhos[N_FILHOS];
  pid_t pid_netos[N_NETOS];

  for (int i = 0; i < N_FILHOS; i++) {
    fflush(stdout);
    pid_filhos[i] = fork();
    if (pid_filhos[i]) {
    } else {
      printf("Processo %d, filho de %d\n", getpid(), getppid());
      for (int i = 0; i < N_NETOS; i++) {
        fflush(stdout);
        pid_netos[i] = fork();
        if (pid_netos[i]) {
        } else {
          printf("Processo %d, filho de %d\n", getpid(), getppid());
          sleep(5);
          printf("Processo %d finalizado\n", getpid());
          exit(1);
        }
      }
      waitpid(0,&status,WUNTRACED);
      printf("Processo %d finalizado\n", getpid());
      exit(1);
    }
  }

  waitpid(0,&status,WUNTRACED);
  printf("Processo principal %d finalizado\n", getpid());

  return 0;
}
