[bits 16]

%define VERSION "0.1"
%define ENDL 0x0A, 0x0D

syscall_vectors:
	jmp main			; 0000h - Kernel main
	jmp clear 			; 0003h
	jmp putchar			; 0006h
	jmp puts			; 0009h
	jmp getchar			; 000Ch
	jmp gets			; 000Fh

main:
	; Устанавливаем стек
	cli
	xor ax, ax
	mov ax, ss
	mov sp, 0FFFFh
	sti

	; Устанавливаем сегменты
	mov ax, 2000h
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	call clear

	mov si, msg_welcome
	call 0000h

	cli
	hlt

%include 'src/kernel/io.asm'

msg_welcome db "Welcome to Minios!", ENDL, 0

buffer times 1024 db 0
