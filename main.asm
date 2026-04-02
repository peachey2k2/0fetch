include "header.inc" ; ELF header
include "macros.inc" ; macros and some common procedures

;;;;;;;;;; code ;;;;;;;;;;
main:

  ; we'll return after setting up the allocations
  mov         rbp, rsp

  ; r14 will always point to uname struct
  sub         rsp, PROG_DATA_SIZE
  mov         r14, rsp
  
  xchg        rsp, rbp

  ; and r15 will always point to the current pos in buffer
  lea         r15, [d.main_buffer]

  ; first, we need to get to envp
  pop         rcx ; argc
  inc         rcx ; +1 for nullptr at the end
  shl         rcx, 3
  add         rsp, rcx ; skip over argv

  mov         ebx, 4

  lea         eax, [placeholder]
  mov         [d.desktop], rax
  mov         [d.session_type], rax
  mov         [d.shell], rax
  mov         [d.username], rax

.loop_envvar_scan:
  pop         rsi
  test        ebx, ebx
  jz          .end_envvar_scan
  test        rsi, rsi
  jz          .end_envvar_scan

  ; SAFETY: precheck lengths to avoid a potential segfault
  strlen      rsi
  cmp         ecx, 20
  jge         .check_desktop
  cmp         ecx, 17
  jge         .check_session_type
  cmp         ecx, 6
  jge         .check_shell
  cmp         ecx, 5
  jge         .check_user
  jmp         .loop_envvar_scan

.check_desktop:
  cmp         dword [rsi], "XDG_"
  jne         .check_session_type
  cmp         dword [rsi+4], "CURR"
  jne         .check_session_type_2
  cmp         dword [rsi+8], "ENT_"
  jne         .loop_envvar_scan
  cmp         dword [rsi+12], "DESK"
  jne         .loop_envvar_scan
  cmp         dword [rsi+16], "TOP="
  jne         .loop_envvar_scan

  add         rsi, 20
  mov         [d.desktop], rsi
  dec         ebx
  jmp         .loop_envvar_scan

.check_session_type:
  cmp         dword [rsi], "XDG_"
  jne         .check_shell
.check_session_type_2:
  cmp         dword [rsi+4], "SESS"
  jne         .loop_envvar_scan_hoop
  cmp         dword [rsi+8], "ION_"
  jne         .loop_envvar_scan_hoop
  cmp         dword [rsi+12], "TYPE"
  jne         .loop_envvar_scan_hoop
  cmp         byte [rsi+16], "="
  jne         .loop_envvar_scan_hoop

  add         rsi, 17
  mov         [d.session_type], rsi
  dec         ebx
  jmp         .loop_envvar_scan

; SIZE: this exists for the sake of short jumps
.loop_envvar_scan_hoop:
  jmp         .loop_envvar_scan

.check_shell:
  cmp         dword [rsi], "SHEL"
  jne         .check_user
  cmp         word [rsi+4], "L="
  jne         .loop_envvar_scan_hoop

  ; SAFETY: in case if $SHELL doesn't contain a slash
  mov         byte [rsi+5], "/"

  lea         rdi, [rsi+6]
  not         ecx ; SIZE: this saves 3 bytes over `mov ecx, -1`, works since rcx will always be a small positive num (length of current env var)
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
  jmp         .loop_envvar_scan_hoop

.check_user:
  cmp         dword [rsi], "USER"
  jne         .loop_envvar_scan_hoop
  cmp         byte [rsi+4], "="
  jne         .loop_envvar_scan_hoop

  add         rsi, 5
  mov         [d.username], rsi
  dec         ebx
  jmp         .loop_envvar_scan_hoop

.end_envvar_scan:
  mov         rsp, rbp

  ; int open(const char *path, int flags, /* mode_t mode */ );
  mov         eax, SYS_open
  mov         edi, os_release_dir ; SAFETY: truncating is fine since it's guaranteed to be within bounds
  xor         esi, esi ; O_RDONLY
  ; mode doesn't matter
  syscall
  cmp         eax, 0
  jl          .ERR_failed_to_read_os_release

  ; ssize_t read(int fd, void buf[count], size_t count);
  push        rax ; fd
  mov         rdi, rax
  xor         eax, eax ; SYS_read
  lea         rsi, [d.main_buffer]
  mov         rdx, BUFFER_SIZE
  syscall
  cmp         rax, 0
  jl          .ERR_failed_to_read_os_release

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
  jl          .ERR_couldnt_find_system_info

  cmp         dword [rsi], "PRET"
  jne         .os_release_next
  cmp         dword [rsi+4], "TY_N"
  jne         .os_release_next
  cmp         dword [rsi+8], "AME="
  jne         .os_release_next

  mov         rbx, rsi
  add         rbx, 13
  lea         r10, [d.system]
  move_str_10 r10, rbx
  dec         ecx
  mov         [d.system_len], rcx


  ;; we have to use /proc/meminfo for available ram since sysinfo doesn't have that
  mov         eax, SYS_open
  mov         edi, meminfo_dir ; SAFETY: truncating is fine since it's guaranteed to be within bounds
  xor         esi, esi ; O_RDONLY
  syscall
  test        eax, eax
  jl          .ERR_failed_to_read_meminfo

  push        rax ; fd
  mov         rdi, rax
  xor         eax, eax ; SYS_read
  lea         rsi, [d.main_buffer]
  mov         edx, BUFFER_SIZE
  syscall
  test        eax, eax
  jl          .ERR_failed_to_read_meminfo

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
  jl          .ERR_couldnt_find_mem_available

  cmp         dword [rsi], "MemA"
  jne         .meminfo_next
  cmp         dword [rsi+4], "vail"
  jne         .meminfo_next
  cmp         dword [rsi+8], "able"
  jne         .meminfo_next

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

  mov         eax, SYS_open
  mov         edi, cpuinfo_dir ; SAFETY: truncating is fine since it's guaranteed to be within bounds
  xor         esi, esi ; O_RDONLY
  syscall
  test        eax, eax
  jl          .ERR_failed_to_read_cpuinfo

  push        rax ; fd
  mov         rdi, rax
  xor         eax, eax ; SYS_read
  lea         rsi, [d.main_buffer]
  mov         edx, BUFFER_SIZE
  syscall
  test        eax, eax
  jl          .ERR_failed_to_read_cpuinfo

  pop         rdi
  push        rax ; byte count
  mov         eax, SYS_close
  syscall

  lea         rsi, [d.main_buffer]
  pop         rcx
  jmp         @f

.cpuinfo_next:
  dec         ecx
  inc         rsi

@@:
  cmp         rcx, 13
  jl          .ERR_couldnt_find_cpu_name

  cmp         dword [rsi], "mode"
  jne         .cpuinfo_next
  cmp         dword [rsi+4], "l na"
  jne         .cpuinfo_next
  cmp         word [rsi+8], "me"
  jne         .cpuinfo_next

  add         rsi, 10

@@:
  inc         rsi
  cmp         byte [rsi], ":"
  jne         @b

  add         rsi, 2
  lea         r11, [d.cpu_name]
  move_str_10 r11, rsi
  mov         [d.cpu_name_len], rcx

  ; int uname(struct utsname *buf);
  mov         eax, SYS_uname
  lea         rdi, [d.utsname]
  syscall
  test        rax, rax
  jnz         .ERR_uname_failed
@@:

  ; int sysinfo(struct sysinfo *info);
  mov         eax, SYS_sysinfo
  lea         rdi, [d.sysinfo]
  syscall
  test        rax, rax
  jnz         .ERR_sysinfo_failed
@@:

  ; int statfs(const char *path, struct statfs *buf);
  mov         eax, SYS_statfs
  mov         rdi, root_path
  lea         rsi, [d.statvfs]
  syscall
  test        rax, rax
  jnz         .ERR_statfs_failed
@@:

  ;; line 1, host name and username
  move_str_n  r15, logo_line_1, logo_line_1_size
  add         r15, logo_line_1_size

  mov         word [r15], 0x5B1B ; "\e["
  mov         dword [r15+2], "33m"
  add         r15, 5

  mov         rdi, [d.username]
  call        move_str_0
  add         r15, rcx

  mov         dword [r15], 0x31335B1B ; "\e[31"
  mov         dword [r15+4], 0x5B1B406D ; "m@\e["
  mov         dword [r15+8], "32m"
  add         r15, 11

  lea         rdi, [d.utsname.nodename]
  call        move_str_0
  add         r15, rcx

  mov         dword [r15], 0x6D305B1B ; "\e[0m"
  mov         dword [r15+4], 0x0A7E20 ; " ~\n"
  add         r15, 7

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

  ;; line 5, uptime
  move_str_n  r15, logo_line_5, logo_line_5_size
  add         r15, logo_line_5_size

  mov         rax, [d.sysinfo.uptime]
  xor         edx, edx
  mov         ebx, 60*60*24
  div         rbx
  push        rdx
  
  test        rax, rax
  jz          .skip_days
  push        rax

  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  pop         rax
  mov         dword [r15], " day"
  cmp         eax, 1
  ja          @f
  mov         word [r15+4], ", "
  add         r15, 6
  jmp         .skip_days
@@:
  mov         dword [r15+4], "s,  "
  add         r15, 7

.skip_days:
  pop         rax
  xor         edx, edx
  mov         ebx, 60*60
  div         rbx
  push        rdx

  test        rax, rax
  jz          .skip_hours
  push        rax

  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  pop         rax
  mov         dword [r15], " hou"
  cmp         eax, 1
  ja          @f
  mov         dword [r15+4], "r,  "
  add         r15, 7
  jmp         .skip_hours
@@:
  mov         dword [r15+4], "rs, "
  add         r15, 8

.skip_hours:
  pop         rax
  xor         edx, edx
  mov         ebx, 60
  div         rbx

  test        rax, rax
  jz          .skip_minutes
  push        rax

  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  pop         rax
  mov         dword [r15], " min"
  cmp         eax, 1
  ja          @f
  mov         dword [r15+4], "ute "
  add         r15, 7
  jmp         .skip_minutes
@@:
  mov         dword [r15+4], "utes"
  add         r15, 8

.skip_minutes:
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
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], " GiB"
  mov         dword [r15+4], " / "
  add         r15, 7

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
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], " GiB"
  mov         dword [r15+4], 0x5B1B2820 ; " (\[e"
  mov         dword [r15+8], "36m"
  add         r15, 11

  pop         rbx
  pop         rax
  xor         edx, edx
  div         rbx ; SAFETY: since we use KiB counts to compare, it can easily end up above 2^32, so we can't go with ebx
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], 0x305B1B25 ; "%\e[0"
  mov         dword [r15+4], 0x0A296D ;"m)\n"
  add         r15, 7


  ;; line 8, storage
  move_str_n  r15, logo_line_8, logo_line_8_size
  add         r15, logo_line_8_size


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
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], " GiB"
  mov         dword [r15+4], " /  "
  add         r15, 7

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
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         byte [r15], "."
  inc         r15

  pop         rax
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], " GiB"
  mov         dword [r15+4], 0x5B1B2820 ; " (\[e"
  mov         dword [r15+8], "36m"
  add         r15, 11

  pop         rbx
  pop         rax
  xor         edx, edx
  div         rbx ; SAFETY: since we use KiB counts to compare, it can easily end up above 2^32, so we can't go with ebx
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], 0x305B1B25 ; "%\e[0"
  mov         dword [r15+4], 0x0A296D ;"m)\n"
  add         r15, 7

  ;; line 9, cpu and load
  move_str_n  r15, logo_line_9, logo_line_9_size
  add         r15, logo_line_9_size

  lea         rax, [d.cpu_name]
  move_str_n  r15, rax, [d.cpu_name_len]
  add         r15, [d.cpu_name_len]

  mov         dword [r15], 0x5B1B2820 ; " (\e["
  mov         dword [r15+4], "36m"
  add         r15, 7

  mov         rax, [d.sysinfo.loads]
  push        ax
  shr         rax, 16
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         byte [r15], "."
  inc         r15

  pop         rax
  and         rax, 0xFFFF
  mov         rbx, 100
  mul         rbx
  shr         rax, 16
  call        dw_to_str
  move_str_n  r15, r13, rbx
  add         r15, rbx

  mov         dword [r15], 0x305B1B25 ; "%\e[0"
  mov         dword [r15+4], 0x0A296D ;"m)\n"
  add         r15, 7

  ;; line 10, colors
  move_str_n  r15, logo_line_10, logo_line_10_size
  add         r15, logo_line_10_size

  ;; aaaand redeem
  lea         rbx, [d.main_buffer]
  sub         r15, rbx
  mov         eax, 1 ; SYS_write ; TODO: uses parts of elf header for 1
  mov         edi, 1 ; stdout
  lea         rsi, [d.main_buffer]
  mov         rdx, r15
  syscall

  xor         dil,dil ; NOTE: sys_exit internally masks this with 0xFF
.end:
  mov         eax, SYS_exit
  syscall

;;;;;;;;;; errors ;;;;;;;;;;

; TODO: we should never be erroring
.ERR_failed_to_read_os_release:
  mov         dil,  101
  jmp         .end
.ERR_couldnt_find_system_info:
  mov         dil,  102
  jmp         .end
.ERR_failed_to_read_meminfo:
  mov         dil,  103
  jmp         .end
.ERR_couldnt_find_mem_available:
  mov         dil,  104
  jmp         .end
.ERR_failed_to_read_cpuinfo:
  mov         dil,  105
  jmp         .end
.ERR_couldnt_find_cpu_name:  
  mov         dil,  106
  jmp         .end
.ERR_uname_failed:
  mov         dil,  107
  jmp         .end
.ERR_sysinfo_failed:
  mov         dil,  108
  jmp         .end
.ERR_statfs_failed:
  mov         dil,  109
  jmp         .end

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
  .desktop       rq 1
  .system        rb 64
  .system_len    rq 1
  .cpu_name      rb 64
  .cpu_name_len  rq 1
  mov         [d.cpu_name_len], rcx
  .mem_available rq 1

  .main_buffer  rb 2048
  .extra_buffer rb 32
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
cpuinfo_dir    db "/proc/cpuinfo", 0
root_path      db "/", 0

placeholder db "<N/A>"
placeholder_size = $ - placeholder

logo_line_1 db 10, 27, "[36m⠀⠀⠀⠀⠠⣿⣧⠀⠀", 27, "[34m⢻⣿⡄⠀⣼⣿⠆⠀⠀ ⠀⠀"
logo_line_1_size = $ - logo_line_1
logo_line_2 db 27, "[36m⠀⠀⠀⣀⣀⣹⣿⣧⣀⣀", 27, "[34m⢻⣿⣾⣿⠏⠀⠀", 27, "[36m⣀⠀ ⠀", 27, "[36m  ", 27, "[34msystem", 27, "[0m  "
logo_line_2_size = $ - logo_line_2
logo_line_3 db 27, "[36m⠀⠀⠼⠿⠿⠿⠿⠿⠿⠿⠆", 27, "[34m⠻⣿⣯⠀⠀", 27, "[36m⣼⣿⠃ ⠀", 27, "[36m  [34mkernel", 27, "[0m  "
logo_line_3_size = $ - logo_line_3
logo_line_4 db 27, "[34m⠀⠀⠀⠀⢠⣿⡟⠀⠀⠀⠀⠀", 27, "[34m⠹⣿⠃", 27, "[36m⣼⣿⠃⠀ ⠀", 27, "[36m  ", 27, "[34mshell", 27, "[0m   "
logo_line_4_size = $ - logo_line_4
logo_line_5 db 27, "[34m⢾⣿⣿⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀", 27, "[36m⣼⣿⣿⣿⣿⡷ ", 27, "[36m  ", 27, "[34muptime", 27, "[0m  "
logo_line_5_size = $ - logo_line_5
logo_line_6 db 27, "[34m⠀⠀⢠⣿⡟", 27, "[36m⢠⣿⣆⠀⠀⠀⠀⠀", 27, "[36m⣼⣿⠃⠀⠀⠀⠀ ", 27, "[36m  ", 27, "[34mdesktop", 27, "[0m "
logo_line_6_size = $ - logo_line_6
logo_line_7 db 27, "[34m⠀⠀⠻⠟⠀⠀", 27, "[36m⣻⣿⣦", 27, "[34m⠰⣶⣶⣶⣶⣶⣶⣶⡖⠀ ⠀", 27, "[36m  ", 27, "[34mmemory", 27, "[0m  "
logo_line_7_size = $ - logo_line_7
logo_line_8 db 27, "[36m⠀⠀⠀⠀⠀⣰⣿⡿⣿⣧", 27, "[34m⠈⠉⠙⣿⣿⡉⠉⠀⠀⠀ ", 27, "[36m󱥎  [34mstorage", 27, "[0m "
logo_line_8_size = $ - logo_line_8
logo_line_9 db 27, "[36m⠀⠀⠀⠀⠰⣿⡟⠀⠘⣿⣧⠀⠀", 27, "[34m⠘⣿⡗⠀⠀⠀ ⠀", 27, "[36m  [34mcpu    ", 27, "[0m "
logo_line_9_size = $ - logo_line_9
logo_line_10 db "                     ", 27, "[36m  ", 27, "[34mpalette", 27, "[0m ", 27, "[34m  ", 27, "[36m  ", 27, "[32m  ", 27, "[33m  ", 27, "[31m  ", 27, "[35m  ", 27, "[0m", 10


; SAFETe: linux pads end of the program with 0 bytes in memory, so
; it's safe to read this as a qword
_10 db 10

logo_line_10_size = $ - logo_line_10
