#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

//        (pai)
//          |
//      +---+---+
//      |       |
//     sed    grep

// ~~~ printfs  ~~~
//        sed (ao iniciar): "sed PID %d iniciado\n"
//       grep (ao iniciar): "grep PID %d iniciado\n"
//          pai (ao iniciar): "Processo pai iniciado\n"
// pai (após filho terminar): "grep retornou com código %d,%s encontrou silver\n"
//                            , onde %s é
//                              - ""    , se filho saiu com código 0
//                              - " não" , caso contrário

// Obs:
// - processo pai deve esperar pelo filho
// - 1º filho deve trocar seu binário para executar "grep silver text"
//   + dica: use execlp(char*, char*...)
//   + dica: em "grep silver text",  argv = {"grep", "silver", "text"}
// - 2º filho, após o término do 1º deve trocar seu binário para executar
//   sed -i /silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g text
//   + dica: leia as dicas do grep

int main(int argc, char** argv) {
    printf("Processo pai iniciado\n");
    int status;
    pid_t pid_2;
    fflush(stdout);
    pid_t pid_1 = fork();
    if (pid_1) {
        waitpid(pid_1, &status, 0);
        fflush(stdout);
        pid_2 = fork();
        if (pid_2) {
        } else {
            printf("grep PID %d iniciado\n", getpid());
            fflush(stdout);
            int s = execlp("/bin/grep", "grep", "adamantium", "text", NULL);
            exit(s);
        }
    } else {
        printf("sed PID %d iniciado\n", getpid());
        fflush(stdout);
        execlp("/bin/sed", "sed", "-i", "-e", "s/silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g", "text", NULL);
        exit(1);
    }

    waitpid(pid_2, &status, 0);
    printf("grep retornou com código %d,%s encontrou adamantium\n", WEXITSTATUS(status), status ? " não" : "");
    return 0;
}
