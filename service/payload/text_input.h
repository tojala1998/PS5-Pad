#ifndef QP_TEXT_INPUT_H
#define QP_TEXT_INPUT_H
#include <stddef.h>
#include <stdint.h>
struct text_job { uint8_t text[128]; unsigned length,index; int active,held,cleanup,status; uint64_t due,started; };
int text_begin(struct text_job *job,int32_t user,const uint8_t *text,size_t length,uint64_t now);
void text_cancel(struct text_job *job,int status);
/* Returns 1 when input and keyboard removal have completed. */
int text_tick(struct text_job *job,uint64_t now);
int text_backend_open(int32_t user);
int text_backend_report(uint8_t modifiers,uint8_t key);
int text_backend_close(void);
#endif
