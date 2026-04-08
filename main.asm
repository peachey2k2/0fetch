include "header.inc"    ; ELF header
include "procs.inc"     ; macros and procedures
include "syscalls.inc"  ; syscall constants


version:
  mov rsi, .prog_version
  mov rdx, prog_version_size
  jmp print_and_end

.prog_version db "0fetch v", VERSION, " ", LATEST_COMMIT, 10

prog_version_size = $ - .prog_version


;;;;;;;;;; code ;;;;;;;;;;
main:
  ; we'll return after setting up the allocations
  mov         rbp, rsp

  ; r14 will always point to uname struct
  lea         r14, [rsp - PROG_DATA_SIZE]
  
  xchg        rsp, rbp

  ; and r15 will always point to the current pos in buffer
  lea         r15, [d.main_buffer]

  ; first, we need to get to envp
  pop         rcx ; argc

  cmp         rcx, 1 ; idc, any arg will bring up the version
  ja short    version
  
  lea         rsp, [rsp + rcx*8 + 8] ; skip argv

  mov         ebx, 5

  lea         eax, [placeholder]
  mov         [d.desktop], rax
  mov         [d.session_type], rax
  mov         [d.shell], rax
  mov         [d.username], rax
  mov         [d.terminal], rax

.loop_envvar_scan:
  pop         rsi
  test        ebx, ebx
  jz short    .end_envvar_scan_hoop

  ; SIZE: stack starts at 0x0000_8000_0000_0000 and goes down, and we aren't realisticly
  ; gonna have 4GB of environment vars so using esi over rsi should be safe. 1 byte saved lol
  test        esi, esi
.end_envvar_scan_hoop:
  jz near     .end_envvar_scan

  ; SAFETY: precheck lengths to avoid a potential segfault
  mov         rdi, rsi
  not         ecx ; SIZE: this is fine since rcx should be argc
  xor         al, al
  repne scasb

  ; SIZE: we used to have a `not` and an `inc` on ecx but we can just prebake that on compared values instead
  cmp         ecx, not 20 + 1
  jbe short   .check_desktop
  cmp         ecx, not 17 + 1
  jbe short   .check_session_type
  cmp         ecx, not 13 + 1
  jbe near    .check_terminal
  cmp         ecx, not 6 + 1
  jbe near    .check_shell
  cmp         ecx, not 5 + 1
  jbe near    .check_user
  jmp short   .loop_envvar_scan_hoop_1

.check_desktop:
  cmp         dword [rsi], "XDG_"
  jne short   .check_session_type

  mov         rax, "CURRENT_"
  cmp         qword [rsi+4], rax
  jne short   .check_session_type_2
  mov         rax, "DESKTOP="
  cmp         qword [rsi+12], rax
  jne short   .loop_envvar_scan

  add         rsi, 20
  mov         [d.desktop], rsi
  dec         ebx
.loop_envvar_scan_hoop_1:
  jmp short   .loop_envvar_scan

.check_session_type:
  cmp         dword [rsi], "XDG_"
  jne short   .check_terminal
.check_session_type_2:
  mov         rax, "SESSION_"
  cmp         qword [rsi+4], rax
  jne short   .loop_envvar_scan_hoop_1
  cmp         dword [rsi+12], "TYPE"
  jne short   .loop_envvar_scan_hoop_1
  cmp         byte [rsi+16], "="
  jne short   .loop_envvar_scan_hoop_1

  add         rsi, 17
  mov         [d.session_type], rsi
  dec         ebx
  jmp short   .loop_envvar_scan_hoop_2

.check_terminal:
  cmp         dword [rsi], "TERM"
  jne short   .check_alacritty
  mov         rax, "_PROGRAM"
  cmp         qword [rsi+4], rax
  jne short   .loop_envvar_scan_hoop_2
  cmp         byte [rsi+12], "="
  jne short   .loop_envvar_scan_hoop_2

  add         rsi, 13
  jmp short   .end_check_terminal

.check_alacritty:
  cmp         dword [rsi], "ALAC"
  jne short   .check_kitty
  mov         rax, "RITTY_LO"
  cmp         qword [rsi+4], rax
  jne short   .loop_envvar_scan_hoop_2
  mov         rsi, alacritty
  jmp short   .end_check_terminal

.check_kitty:
  mov         rax, "KITTY_IN"
  cmp         qword [rsi], rax
  jne short   .check_shell
  mov         rsi, kitty

.end_check_terminal:
  mov         [d.terminal], rsi
  dec         ebx

; SIZE: this exists for the sake of short jumps
.loop_envvar_scan_hoop_2:
  jmp near   .loop_envvar_scan

.check_shell:
  cmp         dword [rsi], "SHEL"
  jne short   .check_user
  cmp         word [rsi+4], "L="
  jne short   .loop_envvar_scan_hoop_2

  mov         byte [rsi+5], "/" ; SAFETY: in case if $SHELL doesn't contain a slash

  lea         rdi, [rsi+6]
  ; SAFETY: use a full count for the forward/reverse scasb pair so the reverse
  ; scan can always reach the last slash in $SHELL.
  mov         ecx, -1
  xor         al, al ; 0
  repne scasb

  std
  ; SIZE: and we'll still have a very high number in ecx by now, so another -5 bytes 
  mov         al, "/"
  repne scasb
  cld

  add         rdi, 2
  mov         [d.shell], rdi
  dec         ebx
  jmp short   .loop_envvar_scan_hoop_2

.check_user:
  cmp         dword [rsi], "USER"
  jne short   .loop_envvar_scan_hoop_2
  cmp         byte [rsi+4], "="
  jne short   .loop_envvar_scan_hoop_2

  add         rsi, 5
  mov         [d.username], rsi
  dec         ebx
  jmp short   .loop_envvar_scan_hoop_2

.end_envvar_scan:
  mov         rsp, rbp

  ; int open(const char *path, int flags, /* mode_t mode */ );
  mov         eax, SYS_open
  mov         edi, os_release_dir ; SAFETY: truncating is fine since it's guaranteed to be within bounds
  xor         esi, esi ; O_RDONLY
  ; mode doesn't matter
  syscall
  test        eax, eax
  js          ERR_failed_to_read_os_release

  ; ssize_t read(int fd, void buf[count], size_t count);
  push        rax ; fd
  mov         rdi, rax
  xor         eax, eax ; SYS_read
  lea         rsi, [d.main_buffer]
  mov         rdx, BUFFER_SIZE
  syscall
  test        rax, rax
  js          ERR_failed_to_read_os_release

  pop         rdi
  push        rax ; byte count
  mov         eax, SYS_close
  syscall

  lea         rsi, [d.main_buffer]
  pop         rcx
  jmp         @f

.os_release_next:
  dec         ecx
  inc         rsi

@@:
  cmp         ecx, 12
  jl          ERR_couldnt_find_system_info

  cmp         dword [rsi], "PRET"
  jne short   .os_release_next
  cmp         dword [rsi+4], "TY_N"
  jne short   .os_release_next
  cmp         dword [rsi+8], "AME="
  jne short   .os_release_next

  lea         rbx, [rsi+13]
  lea         r10, [d.system]
  move_str_10 r10, rbx
  dec         ecx
  mov         [d.system_len], rcx


  ; we have to use /proc/meminfo for available ram since sysinfo doesn't have that
  mov         eax, SYS_open
  mov         edi, meminfo_dir ; SAFETY: truncating is fine since it's guaranteed to be within bounds
  xor         esi, esi ; O_RDONLY
  syscall
  test        eax, eax
  jl          ERR_failed_to_read_meminfo

  push        rax ; fd
  mov         rdi, rax
  xor         eax, eax ; SYS_read
  lea         rsi, [d.main_buffer]
  mov         edx, BUFFER_SIZE
  syscall
  test        eax, eax
  jl          ERR_failed_to_read_meminfo

  pop         rdi
  push        rax ; byte count
  mov         eax, SYS_close
  syscall

  lea         rsi, [d.main_buffer]
  pop         rcx
  jmp         @f

.meminfo_next:
  dec         ecx
  inc         rsi

@@:
  cmp         rcx, 13
  jl          ERR_couldnt_find_mem_available

  cmp         dword [rsi], "MemA"
  jne short   .meminfo_next
  cmp         dword [rsi+4], "vail"
  jne short   .meminfo_next
  cmp         dword [rsi+8], "able"
  jne short   .meminfo_next

  add         rsi, 12

@@:
  inc         rsi
  cmp         byte [rsi], " "
  je          @b

  xor         eax, eax
  xor         ebx, ebx
@@:
  mov         bl, byte [rsi]
  cmp         bl, " "
  je          @f
  sub         bl, "0"
  mul         qword [_10]
  add         rax, rbx
  inc         rsi
  jmp         @b

@@:
  mov         [d.mem_available], rax

  mov         eax, 0x80000004
  mov         esi, 32

  ; NOTE: for safety's sake, in theory we should call cpuid with eax = 0x80000000 first
  ; to verify that the cpu supports extended functions up to 0x80000004, but any cpu
  ; made in the last 20 years should support that already
.cpuid_loop:
  push        rax
  cpuid
  lea         rdi, [d.cpu_name + rsi]
  mov         dword [rdi], eax
  mov         dword [rdi+4], ebx
  mov         dword [rdi+8], ecx
  mov         dword [rdi+12], edx
  pop         rax
  dec         eax
  sub         esi, 16
  jns short   .cpuid_loop

  get_cpu_cores_and_threads

  ; int uname(struct utsname *buf);
  mov         eax, SYS_uname
  lea         rdi, [d.utsname]
  syscall
  test        eax, eax
  jnz         ERR_uname_failed
@@:

  ; int sysinfo(struct sysinfo *info);
  mov         eax, SYS_sysinfo
  lea         rdi, [d.sysinfo]
  syscall
  test        eax, eax
  jnz         ERR_sysinfo_failed
@@:

  ; int statfs(const char *path, struct statfs *buf);
  mov         eax, SYS_statfs
  mov         rdi, root_path
  lea         rsi, [d.statvfs]
  syscall
  test        eax, eax
  jnz         ERR_statfs_failed
@@:

  ;; line 1, host name and username
  move_str_n  r15, logo_line_1, logo_line_1_size
  add         r15, logo_line_1_size

  mov         rdi, [d.username]
  call        move_str_0
  add         r15, rcx

  mov         byte [r15], "@"
  inc         r15

  lea         rdi, [d.utsname.nodename]
  call        move_str_0
  add         r15, rcx

  mov         byte [r15], 10
  inc         r15

  ;; line 2, system
  move_str_n  r15, logo_line_2, logo_line_2_size
  add         r15, logo_line_2_size

  lea         rax, [d.system]
  move_str_n  r15, rax, [d.system_len]
  add         r15, [d.system_len]

  mov         byte [r15], 10
  inc         r15

  ;; line 3, kernel
  move_str_n  r15, logo_line_3, logo_line_3_size
  add         r15, logo_line_3_size

  lea         rdi, [d.utsname.sysname]
  call        move_str_0
  add         r15, rcx

  mov         byte [r15], " "
  inc         r15

  lea         rdi, [d.utsname.release]
  call        move_str_0
  add         r15, rcx

  mov         word [r15], " ("
  add         r15, 2

  lea         rdi, [d.utsname.machine]
  call        move_str_0
  add         r15, rcx

  mov         word [r15], 0x0A29 ; ")\n"
  add         r15, 2

  ;; line 4, shell
  move_str_n  r15, logo_line_4, logo_line_4_size
  add         r15, logo_line_4_size

  mov         rdi, [d.shell]
  call        move_str_0
  add         r15, rcx

  mov         byte [r15], 10
  inc         r15

  ;; line 5, terminal
  move_str_n  r15, logo_line_5, logo_line_5_size
  add         r15, logo_line_5_size

  mov         rdi, [d.terminal]
  call        move_str_0
  add         r15, rcx

  mov         byte [r15], 10
  inc         r15

  ;; line 6, desktop
  move_str_n  r15, logo_line_6, logo_line_6_size
  add         r15, logo_line_6_size

  mov         rdi, [d.desktop]
  call        move_str_0
  add         r15, rcx

  mov         word [r15], " ("
  add         r15, 2

  mov         rdi, [d.session_type]
  call        move_str_0
  add         r15, rcx

  mov         word [r15], 0x0A29 ; ")\n"
  add         r15, 2


  ;; line 7, memory
  move_str_n  r15, logo_line_7, logo_line_7_size
  add         r15, logo_line_7_size

  mov         rax, [d.sysinfo.uptime]
  xor         edx, edx
  mov         ebx, 60*60*24
  div         rbx
  push        rdx
  
  test        eax, eax
  jz short    .skip_days
  push        rax

  call        dw_to_str

  pop         rax
  mov         dword [r15], " day"
  mov         word [r15+4], ", "
  add         r15, 6
  cmp         eax, 1
  je short    .skip_days
  mov         dword [r15-2], "s, "
  inc         r15

.skip_days:
  pop         rax
  xor         edx, edx
  mov         ebx, 60*60
  div         rbx
  push        rdx

  test        eax, eax
  jz short    .skip_hours
  push        rax

  call        dw_to_str

  pop         rax
  mov         dword [r15], " hou"
  mov         dword [r15+4], "r, "
  add         r15, 7
  cmp         eax, 1
  je short    .skip_hours
  mov         dword [r15-2], "s, "
  inc         r15

.skip_hours:
  pop         rax
  xor         edx, edx
  mov         ebx, 60
  div         rbx

  test        eax, eax
  jz short    .skip_minutes
  push        rax

  call        dw_to_str

  mov         rax, " minute"
  mov         qword [r15], rax
  add         r15, 7
  cmp         eax, 1
  je short    .skip_minutes
  mov         byte [r15], "s"
  inc         r15

.skip_minutes:
  mov         byte [r15], 10
  inc         r15

  ;; line 8, cpu
  move_str_n  r15, logo_line_8, logo_line_8_size
  add         r15, logo_line_8_size


  lea         rdi, [d.cpu_name]
  call        move_str_0
  add         r15, rcx

  mov         rax, 0x6D36335B1B2820  ; " (\e[36m"
  mov         qword [r15], rax
  add         r15, 7

  mov         rax, [d.sysinfo.loads]
  push        ax
  shr         eax, 16
  call        dw_to_str

  mov         byte [r15], "."
  inc         r15

  pop         ax
  xor         ebx, ebx ; NOTE: not sure if this is necessary
  mov         bl, 100
  mul         ebx
  shr         eax, 16
  call        dw_to_str

  mov         rax, 0x0A296D305B1B25 ; "%\e[0m)\n"
  mov         qword [r15], rax
  add         r15, 7


  ;; line 9, cpu line 2
  move_str_n  r15, logo_line_9, logo_line_9_size
  add         r15, logo_line_9_size

  mov         eax, [d.cpu_cores]
  test        eax, eax
  jnz         @f
  mov         r13, placeholder
  move_str_n  r15, r13, placeholder_size
  add         r15, placeholder_size

  jmp short   .skip_cores

@@:
  call        dw_to_str

.skip_cores:
  mov         rax, " cores"
  mov         qword [r15], rax
  add         r15, 6

  cmp         [d.cpu_p_cores], 0
  je          @f

  mov         word [r15], " ("
  add         r15, 2

  mov         eax, [d.cpu_p_cores]
  call        dw_to_str

  mov         word [r15], "p/"
  add         r15, 2

  mov         eax, [d.cpu_e_cores]
  call        dw_to_str

  mov         word [r15], "e)"
  add         r15, 2

@@:

  mov         word [r15], ", "
  add         r15, 2

  mov         eax, [d.cpu_threads]
  call        dw_to_str

  mov         rax, " threads"
  mov         qword [r15], rax
  mov         byte [r15+8], 10
  add         r15, 9

  ;; no more numbered lines, memory
  move_str_n  r15, logo_line_n, logo_line_n_size
  add         r15, logo_line_n_size
  move_str_n  r15, logo_line_memory, logo_line_memory_size
  add         r15, logo_line_memory_size

  mov         rax, [d.sysinfo.totalram]
  mov         ebx, [d.sysinfo.mem_unit]
  mul         rbx

  mov         ebx, 1024
  div         rbx ; KiB
  sub         rax, [d.mem_available] ; cuz this is KiB too

  mov         rbx, 100
  mul         rbx ; *100 cuz i dont wanna work with floats

  push        rax ; for percentage

  shr         rax, 20 ; KiB -> GiB

  xor         edx, edx
  mov         rbx, 100
  div         rbx ; [rax].[rdx]
  push        rdx
  
  call        dw_to_str

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str

  mov         dword [r15], "G / "
  add         r15, 4

  mov         rax, [d.sysinfo.totalram]
  mov         ebx, [d.sysinfo.mem_unit]
  mul         rbx

  mov         ebx, 1024
  div         rbx ; KiB

  push        rax ; for percentage

  mov         ebx, 100
  mul         rbx ; *100 cuz i dont wanna work with floats

  shr         rax, 20

  xor         edx, edx
  mov         ebx, 100
  div         rbx ; [rax].[rdx]
  push        rdx
  
  call        dw_to_str

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str

  mov         rax, 0x6D36335B1B282047 ; "G (\e[36m"
  mov         qword [r15], rax
  add         r15, 8

  pop         rbx
  pop         rax
  xor         edx, edx
  div         rbx ; SAFETY: since we use KiB counts to compare, it can easily end up above 2^32, so we can't go with ebx
  call        dw_to_str

  mov         rax, 0x0A296D305B1B25 ; "%\e[0m)\n" 
  mov         qword [r15], rax
  add         r15, 7

  ;; storage
  move_str_n  r15, logo_line_n, logo_line_n_size
  add         r15, logo_line_n_size
  move_str_n  r15, logo_line_storage, logo_line_storage_size
  add         r15, logo_line_storage_size

  mov         rax, [d.statvfs.f_frsize]
  mov         rbx, [d.statvfs.f_blocks]
  sub         rbx, [d.statvfs.f_bfree]
  mul         rbx

  mov         ebx, 1024
  div         rbx ; KiB

  mov         rbx, 100
  mul         rbx ; *100 cuz i dont wanna work with floats

  push        rax ; for percentage

  shr         rax, 20

  xor         edx, edx
  mov         rbx, 100
  div         rbx ; [rax].[rdx]
  push        rdx
  
  call        dw_to_str

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str

  mov         dword [r15], "G / "
  add         r15, 4

  mov         rax, [d.statvfs.f_frsize]
  mov         rbx, [d.statvfs.f_blocks]
  mul         rbx

  mov         ebx, 1024
  div         rbx ; KiB

  push        rax ; for percentage

  mov         rbx, 100
  mul         rbx ; *100 cuz i dont wanna work with floats

  shr         rax, 20

  xor         edx, edx
  mov         rbx, 100
  div         rbx ; [rax].[rdx]
  push        rdx

  call        dw_to_str

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str

  mov         rax, 0x6D36335B1B282047 ; "G (\e[36m"
  mov         qword [r15], rax
  add         r15, 8

  pop         rbx
  pop         rax
  xor         edx, edx
  div         rbx ; SAFETY: since we use KiB counts to compare, it can easily end up above 2^32, so we can't go with ebx
  call        dw_to_str

  mov         rax, 0x0A296D305B1B25 ; "%\e[0m)\n" 
  mov         qword [r15], rax
  add         r15, 7


  ;; aaaand redeem
  lea         rbx, [d.main_buffer]
  sub         r15, rbx
  lea         rsi, [d.main_buffer]
  mov         rdx, r15
print_and_end:
  mov         eax, 1 ; SYS_write ; TODO: uses parts of elf header for 1??
  mov         edi, eax ; stdout
  syscall

  xor         dil,dil ; NOTE: sys_exit internally masks this with 0xFF
exit_and_end:
  mov         eax, SYS_exit
  syscall

;;;;;;;;;; errors ;;;;;;;;;;

; TODO: we should never be erroring
ERR_failed_to_read_os_release:
  mov         dil,  101
  jmp short   exit_and_end
ERR_couldnt_find_system_info:
  mov         dil,  102
  jmp short   exit_and_end
ERR_failed_to_read_meminfo:
  mov         dil,  103
  jmp short   exit_and_end
ERR_couldnt_find_mem_available:
  mov         dil,  104
  jmp short   exit_and_end
ERR_uname_failed:
  mov         dil,  107
  jmp short   exit_and_end
ERR_sysinfo_failed:
  mov         dil,  108
  jmp short   exit_and_end
ERR_statfs_failed:
  mov         dil,  109
  jmp short   exit_and_end

;;;;;;;;;; data ;;;;;;;;;;

struc DataStruct {
  .utsname:
    .utsname.sysname    rb 65
    .utsname.nodename   rb 65
    .utsname.release    rb 65
    .utsname.version    rb 65
    .utsname.machine    rb 65
    .utsname.domainname rb 65

  .sysinfo:
    .sysinfo.uptime    rq 1
    .sysinfo.loads     rq 3
    .sysinfo.totalram  rq 1
    .sysinfo.freeram   rq 1
    .sysinfo.sharedram rq 1
    .sysinfo.bufferram rq 1
    .sysinfo.totalswap rq 1
    .sysinfo.freeswap  rq 1
    .sysinfo.procs     rd 1
                       rd 1
    .sysinfo.totalhigh rq 1
    .sysinfo.freehigh  rq 1
    .sysinfo.mem_unit  rd 1
                       rd 1

  .statvfs:
    .statvfs.f_bsize   rq 1
    .statvfs.f_frsize  rq 1
    .statvfs.f_blocks  rq 1
    .statvfs.f_bfree   rq 1
    .statvfs.f_bavail  rq 1
    .statvfs.f_files   rq 1
    .statvfs.f_ffree   rq 1
    .statvfs.f_favail  rq 1
    .statvfs.f_fsid    rq 1
    .statvfs.f_flag    rq 1
    .statvfs.f_namemax rq 1
                       rb 32

  .username      rq 1
  .shell         rq 1
  .session_type  rq 1
  .terminal      rq 1
  .desktop       rq 1
  .system        rb 64
  .system_len    rq 1
  .cpu_name      rb 64
  .mem_available rq 1
  .cpu_threads   rd 1
  .cpu_cores     rd 1
  .cpu_p_cores   rd 1
  .cpu_e_cores   rd 1

  .main_buffer  rb 2048
  .extra_buffer rb 128
}

virtual at r14
  d DataStruct
  PROG_DATA_SIZE = $ - d
end virtual


; this is just for the output buffer. it's small emough
; so i doubt we even need to change the rlimit
BUFFER_SIZE = 2048

os_release_dir db "/etc/os-release", 0
meminfo_dir    db "/proc/meminfo", 0
root_path      db "/", 0

alacritty      db "Alacritty", 0
kitty          db "Kitty", 0

placeholder db "<N/A>", 0
placeholder_size = $ - placeholder

logo_line_1 db 10, 27, "[36m    ⠠⣿⣧  ", 27, "[34m⢻⣿⡄ ⣼⣿⠆     ", 27,"[34m", 27,"[46m ", 27, "[36;42m ", 27, "[32;43m ", 27, "[33;41m ", 27, "[35m", 27, "[0;35m ", 27, "[0;1m"
logo_line_1_size = $ - logo_line_1
logo_line_2 db 27, "[0;36m   ⣀⣀⣹⣿⣧⣀⣀", 27, "[34m⢻⣿⣾⣿⠏  ", 27, "[36m⣀   ", 27, "[36m  ", 27, "[34msystem", 27, "[0m   "
logo_line_2_size = $ - logo_line_2
logo_line_3 db 27, "[36m  ⠼⠿⠿⠿⠿⠿⠿⠿⠆", 27, "[34m⠻⣿⣯  ", 27, "[36m⣼⣿⠃  ", 27, "[36m  ", 27, "[34mkernel", 27, "[0m   "
logo_line_3_size = $ - logo_line_3
logo_line_4 db 27, "[34m    ⢠⣿⡟     ", 27, "[34m⠹⣿⠃", 27, "[36m⣼⣿⠃   ", 27, "[36m󱆃  ", 27, "[34mshell", 27, "[0m    "
logo_line_4_size = $ - logo_line_4
logo_line_5 db 27, "[34m⢾⣿⣿⣿⣿⡟        ", 27, "[36m⣼⣿⣿⣿⣿⡷ ", 27, "[36m  ", 27, "[34mterm   ", 27, "[0m  "
logo_line_5_size = $ - logo_line_5
logo_line_6 db 27, "[34m  ⢠⣿⡟", 27, "[36m⢠⣿⣆     ", 27, "[36m⣼⣿⠃     ", 27, "[36m  ", 27, "[34mdesktop", 27, "[0m  "
logo_line_6_size = $ - logo_line_6
logo_line_7 db 27, "[34m  ⠻⠟  ", 27, "[36m⣻⣿⣦", 27, "[34m⠰⣶⣶⣶⣶⣶⣶⣶⡖   ", 27, "[36m  ", 27, "[34muptime", 27, "[0m   "
logo_line_7_size = $ - logo_line_7
logo_line_8 db 27, "[36m     ⣰⣿⡿⣿⣧", 27, "[34m⠈⠉⠙⣿⣿⡉⠉    ", 27, "[36m  ", 27, "[34mcpu    ", 27, "[0m  "
logo_line_8_size = $ - logo_line_8
logo_line_9 db 27, "[36m    ⠰⣿⡟ ⠘⣿⣧  ", 27, "[34m⠘⣿⡗     ", 27, "[36m󱇫  ", 27, "[34mcores  ", 27, "[0m  "
logo_line_9_size = $ - logo_line_9

logo_line_storage db 27, "[36m󱥎  ", 27, "[34mstorage", 27, "[0m  "
logo_line_storage_size = $ - logo_line_storage

logo_line_memory db 27, "[36m  ", 27, "[34mmemory", 27, "[0m   "
logo_line_memory_size = $ - logo_line_memory

logo_line_n db "                     "
logo_line_n_size = $ - logo_line_n


; SAFETY: linux pads end of the program with 0 bytes in memory, so
; it's safe to read this as a qword
_10 db 10
