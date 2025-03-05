[bits 16]

%define ENDL 0x0D, 0x0A

main:
	call clear

	mov si, msg_welcome
	call puts

	cli
	hlt

%include 'src/io.asm'
%include 'src/string.asm'
%include 'src/terminal.asm'

msg_welcome db "Welcome to Minios!", ENDL, 0
