#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <math.h>

/***************************************************************
 *                          ATENÇÃO!                           *
 * Não altere esse arquivo! Ele será substituido na avaliação! *
 ***************************************************************/

int* generate_set(int start, int end, int step, size_t* out_sz) {
    assert(end >= start);
    if (end == start)
        return NULL;
    size_t size = (size_t)ceil((end-start)/(double)step);
    *out_sz = size; //retorna o tamanho
    int* buf = (int*)malloc(sizeof(int)*size);
    int* p = buf;
    for (int i = start; i < end; i += step)
	*p++ = i;
    return buf;
}

int sets_equal(int* lb, int* le, int* rb, int* re) {
    for (; lb != le && rb != re; ++lb, ++rb) {
	if (*lb != *rb) return 0;
    }
    return 1;
}

/***************************************************************
 *                          ATENÇÃO!                           *
 * Não altere esse arquivo! Ele será substituido na avaliação! *
 ***************************************************************/
