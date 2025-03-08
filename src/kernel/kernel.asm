[bits 16]

%define ENDL 0x0A, 0x0D

main:
	call clear

	mov si, msg_welcome
	call puts

	cli
	hlt

%include 'src/kernel/io.asm'
%include 'src/kernel/string.asm'
%include 'src/kernel/terminal.asm'

msg_welcome db "Welcome to Minios!", ENDL, 0
