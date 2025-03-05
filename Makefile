ASM=nasm
SRC_DIR=src
BUILD_DIR=build
FLOPPY_IMAGE=minios.img

.PHONY: all bootloader kernel clean always

all: clean always $(FLOPPY_IMAGE)

$(FLOPPY_IMAGE): $(BUILD_DIR)/$(FLOPPY_IMAGE)

$(BUILD_DIR)/$(FLOPPY_IMAGE): bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/$(FLOPPY_IMAGE) bs=512 count=2880
	mkfs.fat -F 12 -n "NBOS" $(BUILD_DIR)/$(FLOPPY_IMAGE)
	dd if=$(BUILD_DIR)/boot.bin of=$(BUILD_DIR)/$(FLOPPY_IMAGE) conv=notrunc
	mcopy -i $(BUILD_DIR)/$(FLOPPY_IMAGE) $(BUILD_DIR)/kernel.bin "::kernel.bin"
	mcopy -i $(BUILD_DIR)/$(FLOPPY_IMAGE) file.txt "::file.txt"
	mmd -i $(BUILD_DIR)/$(FLOPPY_IMAGE) "::dir"
	mcopy -i $(BUILD_DIR)/$(FLOPPY_IMAGE) file.txt "::dir/file.txt"

bootloader: $(BUILD_DIR)/boot.bin

$(BUILD_DIR)/boot.bin: $(SRC_DIR)/boot.asm
	$(ASM) -f bin $< -o $@

kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: $(SRC_DIR)/kernel.asm
	$(ASM) -f bin $(SRC) $< -o $@

always:
	mkdir $(BUILD_DIR)

clean:
	rm -f build/*