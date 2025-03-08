bits 16
org 0x7C00

%define ENDL 0x0A, 0x0D

jmp bootloader_start
nop


;
; Заголовок FAT12
;

OEMLabel                    db "MSWIN4.1"      ; Название диска
BytesPerSector              dw 512
SectorsPerCluster           db 1
ReservedSectors             dw 1
FatCount                    db 2
RootDirEntries              dw 224              ; 224 * 32 = 7168 = 14 секторов
LogicalSectors              dw 2880             ; 2880 * 512 = 1.44 МБ
MediaDescriptorType         db 0F0h
SectorsPerFat               dw 9
SectorsPerTrack             dw 18
Heads                       dw 2
HiddenSectors               dd 0
LargeSectors                dd 0
DriveNumber                 dw 0
Signature                   db 41
VolumeID                    dd 00000000h
VolumeLabel                 db "MINIOS     "    ; 11 байт
FileSystem                  db "FAT12   "       ; 8 байт


;
; CODE
;

bootloader_start:
    ; Устанавливаем сегменты данных
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Устанавливаем стек
    mov ax, 07C0h
    mov ax, 544
    cli
    mov ss, ax
    mov sp, 4096
    sti

    mov [DriveNumber], dl      ; Сохраняем номер диска

    mov si, msg_loading
    call print_string

    ; Получаем параметры диска
    push es
    mov ah, 08h
    int 13h
    jc disk_error
    pop es

    and cl, 0x3F
    xor ch, ch
    mov [SectorsPerTrack], cx     ; Количество секторов

    inc dh
    mov [Heads], dh     ; Количество считывающих головок

    ; compute LBA of root directory = reserved + fats * sectors_per_fat
    ; note: this section can be hardcoded
    mov ax, [SectorsPerFat]
    mov bl, [FatCount]
    xor bh, bh
    mul bx                          ; ax = (fats * sectors_per_fat)
    add ax, [ReservedSectors]       ; ax = LBA of root directory
    push ax

    ; compute size of root directory = (32 * number_of_entries) / bytes_per_sector
    mov ax, [RootDirEntries]
    shl ax, 5                           ; ax *= 32
    xor dx, dx                          ; dx = 0
    div word [BytesPerSector]     ; number of sectors we need to read

    test dx, dx                         ; if dx != 0, add 1
    jz read_root_dir
    inc ax                              ; division remainder != 0, add 1
                                        ; this means we have a sector only partially filled with entries

read_root_dir:
    mov cl, al                          ; cl = number of sectors to read = size of root directory
    pop ax                              ; ax = LBA of root directory
    mov dl, [DriveNumber]          ; dl = drive number (we saved it previously)
    mov bx, buffer                      ; es:bx = buffer
    call disk_read

    ; search for kernel.bin
    xor bx, bx
    mov di, buffer

search_kernel:
    mov si, kernel_file
    mov cx, 11                          ; compare up to 11 characters
    push di
    repe cmpsb
    pop di
    je kernel_found

    add di, 32
    inc bx
    cmp bx, [RootDirEntries]
    jl search_kernel

    ; kernel not found
    jmp kernel_not_found

kernel_found:
    ; di should have the address to the entry
    mov ax, [di + 26]                   ; first logical cluster field (offset 26)
    mov [kernel_cluster], ax

    ; load FAT from disk into memory
    mov ax, [ReservedSectors]
    mov bx, buffer
    mov cl, [SectorsPerFat]
    mov dl, [DriveNumber]
    call disk_read

    ; read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

load_kernel_loop:
    ; Read next cluster
    mov ax, [kernel_cluster]
    
    ; not nice :( hardcoded value
    add ax, 31                          ; first cluster = (kernel_cluster - 2) * sectors_per_cluster + start_sector
                                        ; start sector = reserved + fats + root directory size = 1 + 18 + 134 = 33
    mov cl, 1
    mov dl, [DriveNumber]
    call disk_read

    add bx, [BytesPerSector]

    ; compute location of next cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                              ; ax = index of entry in FAT, dx = cluster mod 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                     ; read entry from FAT table at index ax

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8                      ; end of chain
    jae .read_finish

    mov [kernel_cluster], ax
    jmp load_kernel_loop

.read_finish:
    
    ; jump to our kernel
    mov dl, [DriveNumber]          ; boot device in dl

    mov ax, KERNEL_LOAD_SEGMENT         ; set segment registers
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    cli
    hlt

kernel_not_found:
    mov si, msg_kernel_not_found
    call print_string
    jmp reboot

disk_error:
    mov si, msg_disk_error
    call print_string
    jmp reboot


;
; Print string
;
; Параметры:
; - si: строка для печати
;

print_string:
    pusha

.loop:
    lodsb;
    cmp al, 0
    je .done
    mov ah, 0Eh
    int 10h

    jmp .loop

.done:
    popa
    ret

reboot:
    mov ax, 0
    int 16h

    mov ax, 0
    int 19h


;
; Конвертация LDA адреса в CHS адрес
;
; Параметры:
; - ax: LBA адрес
;
; Выход:
; - cx [bits 0-5]: номер сектора
; - cx [bits 6-15]: цилиндр
; - dh: головка
;

lba_to_chs:
    push ax
    push dx

    xor dx, dx                              ; dx = 0
    div word [SectorsPerTrack]        ; ax = LBA / SectorsPerTrack
                                            ; dx = LBA % SectorsPerTrack

    inc dx                                  ; dx = LBA % SectorsPerTrack + 1 = сектор
    mov cx, dx                              ; cx = сектор

    xor dx, dx                              ; dx = 0
    div word [Heads]                    ; ax = (LBA / SectorsPerTrack) / Heads = цилиндр
                                            ; dx = (LBA / SectorsPerTrack) % Heads = головка

    mov ch, al                              ; ch = цилиндр (младшие 8 бит)
    shl ah, 6
    or cl, ah                               ; Поместим старшие 2 бита в CL
    mov dh, dl                              ; dh = головка

    pop ax
    mov dl, al                              ; Восстановим DL
    pop ax
    ret


;
; Чтение сектора с диска
;
; Параметры:
; - ax: LBA адрес
; - cl: номер сектора
; - dl: номер диска
; - es:bx: адрес ячейки в которую будут записаны данные с диска
;

disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax

    mov ah, 02h
    mov di, 3

.retry:
    pusha
    stc
    int 13h
    jnc .done

    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp disk_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; Сброс контроллера диска
;
; Параметры:
; - dl: номер диска
;

disk_reset:
    pusha

    mov ah, 0
    stc
    int 13h
    jc disk_error

    popa
    ret


kernel_file                     db "KERNEL  BIN"
msg_loading                     db "Loading...", ENDL, 0
msg_disk_error                  db "Disk error!", ENDL, 0
msg_kernel_not_found            db "KERNEL.BIN not found!", ENDL, 0
kernel_cluster                  dw 0

KERNEL_LOAD_SEGMENT:        equ 0x2000
KERNEL_LOAD_OFFSET:         equ 0


times 510-($-$$) db 0
dw 0xAA55

buffer: