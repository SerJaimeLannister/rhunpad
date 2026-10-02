# rhunpad: the scratchpad layer. The notes home, untitled notes, autosave, the distraction-free
# mode and the word count live here; open_initial (main.s) starts the pad.
# RHUNPAD_NOW (unix seconds) and RHUNPAD_TZ (a TZif file) pin the clock for tests and scripts.
.include "rhun.inc"

# A debug build asks for the notes folder at every start and keeps the choice for the
# session only; a release build (0) asks once and stores it in the config
.equ PAD_DEBUG, 1

.bss
.p2align 3
home_buf: .zero 4096              # the notes home
note_buf: .zero 4096              # the next untitled note
pad_session: .zero 4096           # the folder chosen this session
move_old: .zero 4096              # changing folders: where the notes are now
move_new: .zero 4096              # ... and where they go
move_msg: .zero 512               # the change-folder dialog line
.globl g_pad_folder_desc
g_pad_folder_desc: .zero 1024     # the settings row under Change Folder
.p2align 3
save_at: .quad 0                  # time_ms of the next autosave
wc_doc: .quad 0                   # word count cache: the document and its version
wc_ver: .quad 0
wc_n: .quad 0
pad_count: .long 0                # notes counted for the change-folder dialog
pad_moved: .long 0
pad_kept: .long 0

.data
.globl g_zen
g_zen: .long 0                    # distraction-free mode: the chrome stays hidden until toggled off
.globl g_save_state
g_save_state: .long 0             # 0 nothing to report, 2 saved, 3 save failed
.globl pad_pick
pad_pick: .long 0                 # the folder picker is open
pad_first: .long 0                # the first note still waits on the folder choice
pad_asked: .long 0                # the picker opened on its own once already
pad_nosave: .long 0               # apply the new folder without writing it to the config
.globl pad_new_note, cmd_pick_welcome

.text

# pad_now() -> unix seconds
FN pad_now
    PROLOGUE
    lea rdi, [rip + .Lenv_now]
    call getenv
    test rax, rax
    jz 1f
    mov rdi, rax
    mov esi, 32
    call parse_u64
    test rdx, rdx
    jnz 9f
1:  call time_now
9:  EPILOGUE

# be32(p) -> eax big-endian (private)
be32:
    movzx eax, byte ptr [rdi]
    shl eax, 8
    movzx ecx, byte ptr [rdi + 1]
    or eax, ecx
    shl eax, 8
    movzx ecx, byte ptr [rdi + 2]
    or eax, ecx
    shl eax, 8
    movzx ecx, byte ptr [rdi + 3]
    or eax, ecx
    ret

# tz_offset(now) -> seconds to add for local time: the offset of the zone's last transition
# at or before now, from /etc/localtime (TZif). 0 without a usable zone file, so UTC.
FN tz_offset
    PROLOGUE 48
    mov [rsp], rdi                # now
    lea rdi, [rip + .Lenv_tz]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov rdi, rax
    jmp 2f
1:  lea rdi, [rip + .Llocaltime]
2:  call file_read_all
    test rax, rax
    jz .Ltz_zero
    mov rbx, rax
    mov r15, rdx                  # length
    cmp r15, 44
    jb .Ltz_free0
    cmp dword ptr [rbx], 0x66695a54   # "TZif"
    jne .Ltz_free0
    lea r12, [rbx + 44]           # the data block (v1), or the second header (v2+)
    mov r13d, 4                   # bytes per transition
    cmp byte ptr [rbx + 4], '2'
    jb .Ltz_counts
    # a v2+ file: past the v1 block (transitions, indices, types, chars, leaps, flags) there
    # is another 44-byte header, then the same data with 64-bit transitions
    lea rdi, [rbx + 32]
    call be32                     # timecnt
    lea r8, [rax + rax*4]         # 5*timecnt: transitions + indices
    lea rdi, [rbx + 36]
    call be32                     # typecnt
    imul rcx, rax, 6
    add r8, rcx
    lea rdi, [rbx + 40]
    call be32                     # charcnt
    add r8, rax
    lea rdi, [rbx + 28]
    call be32                     # leapcnt
    shl rax, 3                    # 8*leapcnt
    add r8, rax
    lea rdi, [rbx + 24]
    call be32                     # isstdcnt
    add r8, rax
    lea rdi, [rbx + 20]
    call be32                     # isutcnt
    add r8, rax
    lea r12, [rbx + 44]
    add r12, r8                   # the second header
    lea rax, [r12 + 44]
    sub rax, rbx
    cmp r15, rax
    jb .Ltz_free0
    mov r13d, 8
.Ltz_counts:
    lea rdi, [r12 + 32]
    call be32
    mov [rsp + 8], rax            # timecnt
    lea rdi, [r12 + 36]
    call be32
    mov [rsp + 16], rax           # typecnt
    test rax, rax
    jz .Ltz_free0
    # the types have to be inside the file: header + transitions + indices + 6*typecnt
    mov rax, [rsp + 8]
    imul rax, r13
    add rax, [rsp + 8]
    mov rcx, [rsp + 16]
    imul rcx, rcx, 6
    add rax, rcx
    lea rax, [r12 + rax + 44]
    sub rax, rbx
    cmp r15, rax
    jb .Ltz_free0
    lea r14, [r12 + 44]           # transitions
    mov rax, [rsp + 8]
    imul rax, r13
    lea rax, [r14 + rax]
    mov [rsp + 24], rax           # transition type indices
    add rax, [rsp + 8]
    mov [rsp + 32], rax           # types
    # lo = the number of transitions at or before now (binary search)
    xor ecx, ecx                  # lo
    mov rdx, [rsp + 8]            # hi = timecnt
1:  cmp rcx, rdx
    jae 2f
    lea rax, [rcx + rdx]
    shr rax, 1                    # mid
    mov rsi, rax
    imul rax, r13
    add rax, r14                  # &transition[mid]
    xor r9d, r9d                  # the value, big-endian
    xor r10d, r10d
11: shl r9, 8
    movzx r11d, byte ptr [rax + r10]
    or r9, r11
    inc r10d
    cmp r10d, r13d
    jb 11b
    cmp r13d, 8
    je 12f
    movsxd r9, r9d                # a v1 transition is a signed 32-bit
12: cmp r9, [rsp]
    jg 13f
    lea rcx, [rsi + 1]            # transition <= now: lo = mid + 1
    jmp 1b
13: mov rdx, rsi                  # hi = mid
    jmp 1b
2:  # before every transition: the first standard type; otherwise the type of the last one
    test rcx, rcx
    jnz 3f
    mov rdx, [rsp + 16]           # typecnt
    mov rdi, [rsp + 32]           # types
    xor r8d, r8d
21: cmp r8, rdx
    jae 4f
    cmp byte ptr [rdi + 4], 0     # isdst
    je 4f
    add rdi, 6
    inc r8
    jmp 21b
3:  mov rax, [rsp + 24]
    movzx r8d, byte ptr [rax + rcx - 1]
4:  cmp r8, [rsp + 16]            # a broken index falls back to type 0
    jb 5f
    xor r8d, r8d
5:  imul rdi, r8, 6
    add rdi, [rsp + 32]
    call be32
    cdqe                          # the offset is a signed 32-bit
    mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
.Ltz_free0:
    mov rdi, rbx
    call mem_free
.Ltz_zero:
    xor eax, eax
    EPILOGUE

# civil_from_days(days) -> eax year, edx month, ecx day  (Howard Hinnant's algorithm)
FN civil_from_days
    PROLOGUE 16
    mov rax, rdi
    add rax, 719468
    cqo
    mov r9d, 146097
    idiv r9                       # era (truncated; days of 1970+ stay positive anyway)
    test rdx, rdx
    jns 1f
    dec rax
    add rdx, r9
1:  mov r10, rdx                  # doe, [0, 146096]
    mov r11, rax                  # era
    mov rax, r10
    xor edx, edx
    mov r8d, 1460
    div r8
    mov [rsp], rax                # doe/1460
    mov rax, r10
    xor edx, edx
    mov r8d, 36524
    div r8
    mov [rsp + 8], rax            # doe/36524
    mov rax, r10
    xor edx, edx
    mov r8d, 146096
    div r8
    mov rcx, r10
    sub rcx, [rsp]
    add rcx, [rsp + 8]
    sub rcx, rax
    mov rax, rcx
    xor edx, edx
    mov r8d, 365
    div r8
    mov r12, rax                  # yoe, [0, 399]
    imul rax, r11, 400
    add rax, r12
    mov r13, rax                  # year
    imul rcx, r12, 365
    mov rax, r12
    shr rax, 2                    # yoe/4
    add rcx, rax
    mov rax, r12
    xor edx, edx
    mov r8, 100
    div r8
    sub rcx, rax
    mov r14, r10
    sub r14, rcx                  # doy, [0, 365]
    imul rax, r14, 5
    add rax, 2
    xor edx, edx
    mov r8d, 153
    div r8
    mov r15, rax                  # mp, [0, 11]
    imul rcx, r15, 153
    add rcx, 2
    mov rax, rcx
    xor edx, edx
    mov r8d, 5
    div r8
    mov rcx, r14
    sub rcx, rax
    inc rcx                       # day, [1, 31]
    lea rdx, [r15 + 3]            # month
    cmp r15, 10
    jb 2f
    lea rdx, [r15 - 9]
2:  cmp rdx, 2
    ja 3f
    inc r13
3:  mov eax, r13d
    mov ecx, ecx
    EPILOGUE

# pad_date(dst) -> dst with "YYYY-MM-DD", the local day
FN pad_date
    PROLOGUE
    mov rbx, rdi
    call pad_now
    mov r12, rax
    mov rdi, rax
    call tz_offset
    add rax, r12                  # local seconds
    cqo
    mov r9d, 86400
    idiv r9
    test rdx, rdx
    jns 1f
    dec rax                       # floor, for times before 1970
1:  mov rdi, rax
    call civil_from_days          # eax year, edx month, ecx day
    mov r8d, eax
    mov r9d, edx
    mov r10d, ecx
    mov r11d, 1000
    mov eax, r8d
    xor edx, edx
    div r11d
    add eax, '0'
    mov [rbx], al
    mov r11d, 100
    mov eax, edx
    xor edx, edx
    div r11d
    add eax, '0'
    mov [rbx + 1], al
    mov r11d, 10
    mov eax, edx
    xor edx, edx
    div r11d
    add eax, '0'
    mov [rbx + 2], al
    add edx, '0'
    mov [rbx + 3], dl
    mov byte ptr [rbx + 4], '-'
    mov eax, r9d
    xor edx, edx
    div r11d
    add eax, '0'
    mov [rbx + 5], al
    add edx, '0'
    mov [rbx + 6], dl
    mov byte ptr [rbx + 7], '-'
    mov eax, r10d
    xor edx, edx
    div r11d
    add eax, '0'
    mov [rbx + 8], al
    add edx, '0'
    mov [rbx + 9], dl
    mov byte ptr [rbx + 10], 0
    mov rax, rbx
    EPILOGUE

# pad_home() -> cstr, the notes home, created if needed ($RHUNPAD_HOME, else the configured
# [files] notes_folder, else ~/rhunpad when nobody can pick a folder). 0: a folder has to be
# chosen first; without one the notes stay in their tabs, unsaved
FN pad_home
    PROLOGUE
    lea rdi, [rip + g_pad_folder_desc]
    lea rsi, [rip + .Lnone_yet]
    call cstr_copy
    xor r12d, r12d                # append /rhunpad to make the default home?
    lea rdi, [rip + .Lenv_pad]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov r12d, 1
    jmp 5f
1:  cmp byte ptr [rip + pad_session], 0
    je 11f
    lea rax, [rip + pad_session]
    jmp 5f
11:
.if PAD_DEBUG == 0
    mov rax, [rip + cfg_pad_folder]
    test rax, rax
    jz 2f
    cmp byte ptr [rax], 0
    jne 5f
.endif
2:  # nothing chosen: headless scripts cannot pick a folder, so they get the default home
    cmp dword ptr [rip + g_headless], 0
    je 9f
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    mov r12d, 1
5:  lea rdi, [rip + home_buf]
    mov rsi, rax
    call cstr_copy
    test r12d, r12d
    jz 4f
    mov rdi, rax
    lea rsi, [rip + .Lpad_dir]
    call cstr_copy
4:  lea rdi, [rip + home_buf]
    call mkdir_p
    lea rdi, [rip + home_buf]
    call file_is_dir
    test eax, eax
    jz 9f
    lea rdi, [rip + g_pad_folder_desc]
    lea rsi, [rip + home_buf]
    call cstr_copy
    lea rax, [rip + home_buf]
9:  EPILOGUE

# pad_note_path() -> cstr of the first free untitled-N.md in the home, neither on disk nor
# among the open tabs (0 without a home)
FN pad_note_path
    PROLOGUE
    call pad_home
    test rax, rax
    jz 9f
    mov rbx, rax
    mov r12d, 1                    # N
1:  lea rdi, [rip + note_buf]
    mov rsi, rbx
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Luntitled]
    call cstr_copy
    mov r13, rax
    mov rdi, rax
    mov esi, r12d
    call fmt_u64
    lea rdi, [r13 + rax]
    lea rsi, [rip + .Lmd]
    call cstr_copy
    lea rdi, [rip + note_buf]
    call file_mtime
    test rax, rax
    jnz 2f
    lea rdi, [rip + note_buf]
    call app_find_tab
    test rax, rax
    jns 2f
    lea rax, [rip + note_buf]
    EPILOGUE
2:  inc r12d
    jmp 1b
9:  xor eax, eax
    EPILOGUE

# pad_assign(doc) -> 1 with the note given its untitled-N.md path (its first save names it);
# 0 without a home, and once the folder picker opens on its own
FN pad_assign
    PROLOGUE
    mov rbx, rdi
    call pad_note_path
    test rax, rax
    jz 1f
    mov rdi, rbx
    mov rsi, rax
    call doc_set_path
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
1:  cmp dword ptr [rip + pad_pick], 0
    jne 2f
    cmp dword ptr [rip + pad_asked], 0
    jne 2f
    mov dword ptr [rip + pad_asked], 1
    xor edi, edi
    call cmd_pick_folder
2:  xor eax, eax
    EPILOGUE

# pad_startup(): an empty pad start: a first note, or the picker on a first launch
FN pad_startup
    call pad_home
    test rax, rax
    jz 1f
    jmp cmd_new_file
1:  mov edi, 1
    jmp cmd_pick_folder

# cmd_pick_folder(first): the notes folder picker; first: the first note follows the choice
FN cmd_pick_folder
    mov dword ptr [rip + pad_pick], 1
    test edi, edi
    jz 1f
    mov dword ptr [rip + pad_first], 1
1:  mov edi, 2
    jmp browse_open

# cmd_change_folder(): Settings: choose a different notes folder
FN cmd_change_folder
    xor edi, edi
    jmp cmd_pick_folder

# pad_folder_picked(path cstr): the picker's choice
FN pad_folder_picked
    PROLOGUE 16
    mov dword ptr [rip + pad_pick], 0
    mov rbx, rdi
    lea rdi, [rip + move_new]
    mov rsi, rbx
    call cstr_copy
    call pad_home                 # the old home, while it is still configured
    mov [rsp], rax
    test rax, rax
    jz 8f
    mov rdi, rax
    lea rsi, [rip + move_new]
    call strcmp_eq
    test eax, eax
    jz 1f
    lea rdi, [rip + .Lsame_folder]
    call app_toast
    EPILOGUE
1:  lea rdi, [rip + move_old]
    mov rsi, [rsp]
    call cstr_copy
    call pad_count_notes
    test eax, eax
    jz 8f
    # notes exist in the old home: move them, or leave them there?
    lea rdi, [rip + move_msg]
    lea rsi, [rip + .Lmove_a]
    call cstr_copy
    mov r12, rax
    mov rdi, rax
    mov esi, [rip + pad_count]
    call fmt_u64
    lea rdi, [r12 + rax]
    lea rsi, [rip + .Lmove_b]
    call cstr_copy
    lea rdi, [rip + .Lchange_q]
    lea rsi, [rip + move_msg]
    lea rdx, [rip + .Luse_new]
    lea rcx, [rip + pad_use_new]
    lea r8, [rip + .Lmove_notes]
    lea r9, [rip + pad_move_notes]
    call app_choice
    EPILOGUE
8:  call pad_apply_folder
    EPILOGUE

# pad_count_notes() -> eax, the top-level .md notes in move_old (also pad_count)
FN pad_count_notes
    mov dword ptr [rip + pad_count], 0
    lea rdi, [rip + move_old]
    lea rsi, [rip + pad_notes_cb]
    xor edx, edx
    call dir_each
    mov eax, [rip + pad_count]
    ret

pad_notes_cb:                      # (ctx, name, is_dir)
    test edx, edx
    jnz 9f
    push rbx
    mov rbx, rsi
    mov rdi, rbx
    call strlen
    mov rsi, rax
    lea rdx, [rip + .Lmd]
    mov rcx, 3
    call str_ends
    test eax, eax
    jz 8f
    inc dword ptr [rip + pad_count]
8:  pop rbx
9:  ret

# pad_apply_folder(): move_new becomes the notes home
FN pad_apply_folder
    PROLOGUE
    # the choice holds for this session; a release build also writes it to the config
    lea rdi, [rip + pad_session]
    lea rsi, [rip + move_new]
    call cstr_copy
    cmp dword ptr [rip + pad_nosave], 0
    jne 1f
.if PAD_DEBUG == 0
    lea rdi, [rip + move_new]
    call strlen
    mov rsi, rax
    lea rdi, [rip + move_new]
    call mem_dup
    mov [rip + cfg_pad_folder], rax
    call config_save
.endif
1:  mov dword ptr [rip + pad_nosave], 0
    mov dword ptr [rip + pad_asked], 0
    call pad_home                 # create it, and refresh the settings row
    test rax, rax
    jz 2f
    mov rdi, rax
    call app_set_project
2:  cmp dword ptr [rip + pad_first], 0
    je 9f
    mov dword ptr [rip + pad_first], 0
    # the chosen folder's session: the notes continue where they were
    call session_restore
    cmp qword ptr [rip + g_tabs + VEC_len], 0
    jne 9f
    call cmd_new_file
9:  EPILOGUE

# pad_materialize(): empty notes without a path become untitled-N.md files, so closing and
# reopening keeps them as they were (before the session is written)
FN pad_materialize
    PROLOGUE
    call pad_home
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, [rip + g_project]
    test rsi, rsi
    jz 9f
    call strcmp_eq
    test eax, eax
    jz 9f                          # not the pad's project: leave scratch tabs alone
    xor r12d, r12d
1:  cmp r12, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 2f
    mov rbx, [rax + TAB_doc]
    cmp qword ptr [rbx + DOC_path], 0
    jne 2f
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz 2f
    mov rdi, rbx
    call doc_dirty
    test eax, eax
    jnz 2f                        # a modified note: the save flow handles it
    mov rdi, rbx
    call pad_assign
    test eax, eax
    jz 2f
    mov rdi, rbx
    call doc_save
2:  inc r12
    jmp 1b
9:  EPILOGUE

# pad_use_new(): the dialog's choice: leave the old notes where they are
FN pad_use_new
    jmp pad_apply_folder

# pad_move_notes(): the dialog's choice: move the old home's notes into the new folder
FN pad_move_notes
    PROLOGUE 16
    mov dword ptr [rip + pad_moved], 0
    mov dword ptr [rip + pad_kept], 0
    lea rdi, [rip + move_old]
    lea rsi, [rip + pad_move_cb]
    xor edx, edx
    call dir_each
    # open tabs follow their files
    xor r12d, r12d
1:  cmp r12, [rip + g_tabs + VEC_len]
    jae 2f
    mov rdi, r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 3f
    mov rbx, [rax + TAB_doc]
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 3f
    call strlen
    mov r13, rax
    lea rdi, [rip + move_old]
    call strlen
    mov r14, rax
    mov rdi, [rbx + DOC_path]
    mov rsi, r13
    lea rdx, [rip + move_old]
    mov rcx, r14
    call str_starts
    test eax, eax
    jz 3f
    mov rdi, [rbx + DOC_path]
    cmp byte ptr [rdi + r14], '/'
    jne 3f
    lea rdi, [rip + move_new]
    mov rsi, [rbx + DOC_path]
    lea rsi, [rsi + r14 + 1]
    call path_join
    mov r15, rax
    mov rdi, r15
    call file_mtime
    test rax, rax
    jz 4f                         # the note stayed behind: so does the tab's path
    mov rdi, rbx
    mov rsi, r15
    call doc_set_path
    mov dword ptr [rip + g_dirty], 1
4:  mov rdi, r15
    call mem_free
3:  inc r12
    jmp 1b
2:  lea rdi, [rip + move_msg]
    lea rsi, [rip + .Lmoved_a]
    call cstr_copy
    mov r12, rax
    mov rdi, rax
    mov esi, [rip + pad_moved]
    call fmt_u64
    lea rdi, [r12 + rax]
    lea rsi, [rip + .Lmoved_b]
    call cstr_copy
    mov r12, rax
    cmp dword ptr [rip + pad_kept], 0
    je 5f
    mov rdi, rax
    lea rsi, [rip + .Lkept]
    call cstr_copy
    mov r12, rax
    mov rdi, rax
    mov esi, [rip + pad_kept]
    call fmt_u64
    lea rdi, [r12 + rax]
    mov byte ptr [rdi], 0
5:  lea rdi, [rip + move_msg]
    call app_toast
    call pad_apply_folder
    EPILOGUE

pad_move_cb:                       # (ctx, name, is_dir): one note across, never over another
    PROLOGUE 16
    test edx, edx
    jnz 9f
    mov rbx, rsi
    mov rdi, rbx
    call strlen
    mov rsi, rax
    lea rdx, [rip + .Lmd]
    mov rcx, 3
    call str_ends
    test eax, eax
    jz 9f
    lea rdi, [rip + move_old]
    mov rsi, rbx
    call path_join
    mov r12, rax
    lea rdi, [rip + move_new]
    mov rsi, rbx
    call path_join
    mov r13, rax
    mov rdi, r13
    call file_mtime
    test rax, rax
    jnz 1f                        # the name is taken: the note stays where it is
    mov rdi, r12
    mov rsi, r13
    SYS SYS_rename
    test rax, rax
    js 1f
    inc dword ptr [rip + pad_moved]
    jmp 2f
1:  inc dword ptr [rip + pad_kept]
2:  mov rdi, r12
    call mem_free
    mov rdi, r13
    call mem_free
9:  EPILOGUE

# pad_folder_cancel(): the picker closed without a choice: no folder, no note — the welcome
# screen's row opens the picker again, as many times as wanted; cancellation is never a choice
FN pad_folder_cancel
    cmp dword ptr [rip + pad_pick], 0
    je 9f
    mov dword ptr [rip + pad_pick], 0
    mov dword ptr [rip + pad_first], 0
    mov dword ptr [rip + pad_asked], 0
9:  ret

# cmd_pick_welcome(): the welcome screen and the command palette: the picker, the first note
# follows the choice
FN cmd_pick_welcome
    mov edi, 1
    jmp cmd_pick_folder

# pad_new_note(i): a note just opened in the pad becomes a file right away, so it exists on
# disk and keeps its name; elsewhere tabs stay unnamed until they are saved
FN pad_new_note
    PROLOGUE
    mov rbx, rdi                  # the tab
    call pad_home
    test rax, rax
    jz 9f
    mov r12, rax
    mov rsi, [rip + g_project]
    test rsi, rsi
    jz 9f
    mov rdi, r12
    call strcmp_eq
    test eax, eax
    jz 9f                          # not the pad's project
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 9f
    mov rbx, [rax + TAB_doc]
    cmp qword ptr [rbx + DOC_path], 0
    jne 9f
    mov rdi, rbx
    call pad_assign
    test eax, eax
    jz 9f
    mov rdi, rbx
    call doc_save
    test rax, rax
    js 1f
    mov dword ptr [rip + g_save_state], 2
    jmp 9f
1:  mov dword ptr [rip + g_save_state], 3
9:  EPILOGUE

# app_autosave(): save every modified file with a path, quietly (cfg_autosave)
FN app_autosave
    PROLOGUE
    cmp dword ptr [rip + cfg_autosave], 0
    je 9f
    xor r12d, r12d
1:  cmp r12, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 2f
    mov rbx, [rax + TAB_doc]
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz 2f
    mov rdi, rbx
    call doc_dirty
    test eax, eax
    jz 2f
    cmp qword ptr [rbx + DOC_path], 0
    jne 4f
    # a new note names itself at its first save
    mov rdi, rbx
    call pad_assign
    test eax, eax
    jz 2f
4:  mov rdi, rbx
    call doc_save
    test rax, rax
    js 3f
    mov dword ptr [rip + g_save_state], 2
    mov rdi, rbx
    call git_doc_saved
    mov dword ptr [rip + g_dirty], 1
    jmp 2f
3:  mov dword ptr [rip + g_save_state], 3
    lea rdi, [rip + .Lsave_failed]
    call app_toast
2:  inc r12
    jmp 1b
9:  EPILOGUE

# pad_tick(): once a second, autosave; called from app_tick
FN pad_tick
    cmp dword ptr [rip + cfg_autosave], 0
    je 9f
    call time_ms
    cmp rax, [rip + save_at]
    jb 9f
    add rax, 1000
    mov [rip + save_at], rax
    jmp app_autosave
9:  ret

# doc_words(doc) -> words in the text, cached by DOC_version
FN doc_words
    PROLOGUE 16
    mov rbx, rdi
    cmp rbx, [rip + wc_doc]
    jne 1f
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + wc_ver]
    jne 1f
    mov rax, [rip + wc_n]
    EPILOGUE
1:  mov [rip + wc_doc], rbx
    mov rax, [rbx + DOC_version]
    mov [rip + wc_ver], rax
    xor r12d, r12d                # words
    xor r13d, r13d                # inside a word
    mov rdi, rbx
    call doc_len
    mov r14, rax
    test rax, rax
    jz 3f
    mov rdi, rbx
    call doc_contiguous
    mov r15, rax
2:  test r14, r14
    jz 3f
    movzx eax, byte ptr [r15]
    inc r15
    dec r14
    cmp al, '!'
    jb 21f                        # anything below ' ' (and space itself) ends a word
    test r13d, r13d
    jnz 2b
    inc r12d
    mov r13d, 1
    jmp 2b
21: xor r13d, r13d
    jmp 2b
3:  mov [rip + wc_n], r12
    mov rax, r12
    EPILOGUE

# cmd_toggle_zen(): distraction-free mode, the chrome away and the page alone
FN cmd_toggle_zen
    xor dword ptr [rip + g_zen], 1
    mov dword ptr [rip + g_dirty], 1
    ret

.section .rodata
.Lenv_now: .asciz "RHUNPAD_NOW"
.Lenv_tz: .asciz "RHUNPAD_TZ"
.Lenv_pad: .asciz "RHUNPAD_HOME"
.Lhome: .asciz "HOME"
.Llocaltime: .asciz "/etc/localtime"
.Lpad_dir: .asciz "/rhunpad"
.Luntitled: .asciz "/untitled-"
.Lmd: .asciz ".md"
.Lsave_failed: .asciz "Could not save the file"
.Lnone_yet: .asciz "Not chosen yet"
.Lsame_folder: .asciz "Already the notes folder"
.Lchange_q: .asciz "Change the notes folder?"
.Lmove_a: .asciz "Move "
.Lmove_b: .asciz " notes to the new folder?"
.Luse_new: .asciz "Use New Folder"
.Lmove_notes: .asciz "Move Notes"
.Lmoved_a: .asciz "Moved "
.Lmoved_b: .asciz " notes"
.Lkept: .asciz ", kept "
