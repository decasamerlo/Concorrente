#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

int* generate_set(int start, int end, int step, size_t* out_sz);
int sets_equal(int* lb, int* le, int* rb, int* re);

int* lower_bound(int value, int* begin, int* end) {
    while ((end-begin) > 1 && *begin != value) { 
        int* mid = begin + (end-begin)/2;
        if (value < *mid) 
            end = mid;
        else 
            begin = mid;
    }
    return begin;
}

size_t merge_join(int* lb, int* le, int* rb, int* re, int* out) {
    size_t size = 0;
    while (lb != le && rb != re) {
        if (*lb == *rb) {
            *out++ = lb[0];
            ++lb;
            ++rb;
            ++size;
        } else if (*lb < *rb) {
            lb = lower_bound(*rb, ++lb, le);
        } else { // *rb < *lb
            rb = lower_bound(*lb, ++rb, re);
        }
    }
    return size;
}

int main(int argc, char **argv) {
    // cria os conjuntos de entrada (a e b), além do resultado esperado (e).
    // a = {0, 1, 2, 3, 4}
    // b =       {2, 3, 4, 5, 6}
    // e =       {2, 3, 4}
    //
    // O terceiro argumento de generate_set é o passo entre os elementos.
    // Por exemplo, generate_set(0, 3, 2) = {0, 2}
    //
    // IMPORTANTE: atente para as variáveis *_sz que recebem do
    // generate_set o número de elementos no set gerado
    size_t a_sz, b_sz, e_sz;
    int* a  = generate_set(0, 5, 1, &a_sz);
    int* b  = generate_set(2, 7, 1, &b_sz);
    int* e  = generate_set(2, 5, 1, &e_sz);

    // calcula o tamanho da intersecção e aloca espaço para o resultado.
    // o script corretor calcula o tamanho exato, pois isso facilita o
    // crash de programas bugados
    size_t c_sz = (size_t)ceil((5-0)/(double)1);
    int* c  = malloc(sizeof(int)*c_sz);

    // computa a intersecção e salva em c
    int* ce = c + merge_join(a, a+a_sz, b, b+b_sz, c);

    // verifica se o resultado em [c, ce) é igual ao esperado em [e, e+e_sz)
    printf("OK: %d\n", sets_equal(c, ce, e, e+e_sz));

    // libera toda a memória usada
    free(a);
    free(b);
    free(c);
    free(e);
    return 0;
}
