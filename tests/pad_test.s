# pad_date: the local date of RHUNPAD_NOW under the zone in RHUNPAD_TZ (a TZif file), on
# stdout; "offset N" first so the zone reader is covered too
.include "rhun.inc"

.bss
.p2align 3
buf: .zero 64

.text
FN main
    PROLOGUE
    call pad_now
    mov rdi, rax
    call tz_offset
    mov rdi, rax
    push rax
    lea rdi, [rip + .Loff]
    call log_cstr
    pop rdi
    call log_u64
    call log_nl
    mov edi, 20359
    call civil_from_days
    push rcx
    push rdx
    push rax
    pop rdi
    call log_u64
    lea rdi, [rip + .Lsp]
    call log_cstr
    pop rdi
    call log_u64
    lea rdi, [rip + .Lsp]
    call log_cstr
    pop rdi
    call log_u64
    call log_nl
    lea rdi, [rip + buf]
    call pad_date
    mov rdi, rax
    call log_cstr
    call log_nl
    xor eax, eax
    EPILOGUE

.section .rodata
.Loff: .asciz "offset "
.Lsp: .asciz " "
