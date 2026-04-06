; sketchiest debug print ever award
macro debug_print {
  push rax
  push rdi
  push rsi
  push rdx
  push rcx
  push rbx
  mov rax, SYS_write
  mov rdi, 1
  mov rsi, root_path
  mov rdx, 1
  syscall
  pop rbx
  pop rcx
  pop rdx
  pop rsi
  pop rdi
  pop rax
}

macro exit code* {
  mov edi, code
  mov eax, SYS_exit
  syscall
}


;; x rax
;; -> rsi, rdi (str pointers)
;; <- rcx (count)
cmp_dwords:
  mov       eax, [rdi]
  cmp       dword [rsi], eax
  jne       @f
  add       rsi, 4
  add       rdi, 4
  dec       rcx
  jne       cmp_dwords
@@:
  ret
  

; TODO: get rid of this
macro move_str_n dest*, src*, n* {
  mov       rsi, src
  mov       rdi, dest
  mov       rcx, n
  rep movsb
}

;; copy `src` to `dest` until null termination
;; -> r15 (dest)
;; -> rdi (src)
move_str_0:
  push        rdi
  mov         rcx, -1
  xor         al, al
  repne scasb
  not         rcx
  dec         rcx
  pop         rsi
  push        rcx
  mov         rdi, r15
  rep movsb
  pop         rcx

  ret

macro move_str_10 dest*, src* {
  mov         rdi, src
  mov         rcx, -1
  mov         al, 10
  repne scasb
  not         rcx
  dec         rcx
  push        rcx
  mov         rsi, src
  mov         rdi, dest
  rep movsb
  pop         rcx
}

;; parse a qword into a string
;; -> eax (number)
;; <- r13 (pos)
;; <- rbx (length)
dw_to_str:
  lea     r13, [d.extra_buffer]
  add     r13, 32
  push    r13
  mov     ebx, 10    ; divisor

@@:
  xor     rdx, rdx   ; divided, upper (also remainder)
  div     ebx

  add     dl, '0'
  dec     r13
  mov     [r13], dl

  test    eax, eax
  jnz     @b

  pop     rbx
  sub     rbx, r13

  move_str_n  r15, r13, rbx
  add         r15, rbx

  ret


; adapted from polaris: https://github.com/NSG650/Polaris/blob/36e33b00ba2204191febe8c19bdfa6fae84f6787/tests/cpuinfo.cxx#L144
macro get_cpu_cores_and_threads {
  local .intel, .amd, .cpu_loop, .found_cores_check_loop, .reloop, .endloop, .end

  ; r12 -> unique core counter
  xor     r12, r12

  ; get the thread count
  mov     eax, 0x0B
  mov     ecx, 1
  cpuid
  and     ebx, 0xFFFF
  mov     [d.cpu_threads], ebx

  xor     eax, eax
  cpuid
  cmp     ebx, "Genu" ; intel -> "GenuineIntel"
  je      .intel
  cmp     ebx, "Auth" ; amd -> "AuthenticAMD"
  je      .amd

  ; unknown cpu
  mov     [d.cpu_cores], 0
  jmp     .end

.intel:
  ; to get the core count on intel, i'd like to just do the easy thing, which is just `threads / smt`
  ; but intel is a bitch and sometimes uses a hybrid architecture. see: https://en.wikipedia.org/wiki/Alder_Lake
  ;
  ; idk if there's a better way to check p/e core counts, cuz i don't like (ab)using sched_setaffinity just for this

  ; NOTE: `cpu_set_t` is 128 bytes long, which is why we need extra_buffer to be 128 bytes
  mov     eax, 0x07
  xor     ecx, ecx
  cpuid
  bt      edx, 15
  ; intel SDM says for leaf 0x07 edx[15] "If 1, the processor is identified as a hybrid part. If
  ; CPUID.00H.MAXLEAF ≥ 1AH and CPUID.1AH:EAX <> 0, then the Native Model ID Enumeration Leaf 1AH exists."
  jc      @f

  ; if it's not a hybrid cpu, just use the same SMT to calculate core count
  mov     eax, 0x0B
  xor     ecx, ecx
  cpuid
  and     ebx, 0xFFFF ; smt
  mov     eax, [d.cpu_threads]
  xor     edx, edx
  div     ebx
  mov     r12d, eax
  jmp     .end
  
@@:
  lea     rdi, [d.extra_buffer]
  mov     ecx, 16 ; 16*8 = 128
  xor     eax, eax
  rep     stosq

  mov     ecx, [d.cpu_threads]
.cpu_loop:
  dec     ecx
  bts     dword [d.extra_buffer], ecx
  push    rcx

  ; int sched_setaffinity(pid_t pid, size_t cpusetsize, const cpu_set_t *mask);
  mov     rax, SYS_sched_setaffinity
  xor     rdi, rdi
  mov     rsi, 128
  lea     rdx, [d.extra_buffer]
  syscall
  test    eax, eax
  js      .end_loop

  mov     eax, 0x1A
  cpuid
  shr     eax, 24 ; 0x20=e 2x40=p
  push    rax

  mov     eax, 0x0B
  xor     ecx, ecx ; just in case
  cpuid
  and     eax, 0x1F
  mov     cl, al
  shr     edx, cl ; physical core id

  pop     rax ; type
  test    r12d, r12d
  jz      @f
  xor     ecx, ecx

.found_cores_check_loop:
  cmp     word [d.main_buffer + 2*rcx], dx
  je      .reloop

  inc     ecx
  cmp     ecx, r12d
  jb      .found_cores_check_loop

@@:
  mov     word [d.main_buffer + 2*r12], dx
  inc     r12d

  cmp     ax, 0x40
  jne     @f
  inc     [d.cpu_p_cores]
  jmp     .reloop
@@:
  cmp     ax, 0x20
  jne     .reloop
  inc     [d.cpu_e_cores]
@@:
  
.reloop:
  pop     rcx
  btr     dword [d.extra_buffer], ecx
  test    ecx, ecx
  jnz     .cpu_loop

.end_loop:
  ; TODO: reset affinity, maybe


.amd:
  ; amd is way easier since we don't need to deal with p/e coree
  ; and amd is nice enough to even bundle the core count directly... how based of them.
  mov     eax, 0x80000008
  cpuid
  and     ecx, 0xFF
  inc     ecx
  mov     [d.cpu_cores], ecx


.end:
  mov     [d.cpu_cores], r12d
}
