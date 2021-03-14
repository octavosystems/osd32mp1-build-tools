#
# SPDX-License-Identifier:	GPL-2.0+

ROOT_DIR = $(PWD)
ATF_VERSION=arm-trusted-firmware-2.0
UBOOT_VERSION = u-boot-2018.11
KERNEL_VERSION=linux-4.19.94
GCNANO_VERSION=6.2.4.p4

FSBL_DIR ?= $(realpath bootloader/$(ATF_VERSION))
SSBL_DIR ?= $(realpath bootloader/$(UBOOT_VERSION))
KERNEL_DIR ?= $(realpath kernel/$(KERNEL_VERSION))
MULTISTRAP_DIR ?= $(realpath multistrap)
ROOTFS_DIR ?= $(MULTISTRAP_DIR)/multistrap-debian-buster
GCNANO_DIR ?= $(realpath gcnano-$(GCNANO_VERSION)-binaries)
GCNANO_DRV_DIR ?= $(GCNANO_DIR)/gcnano-driver-$(GCNANO_VERSION)
GCNANO_USR_DIR ?= $(GCNANO_DIR)/gcnano-userland-multi-$(GCNANO_VERSION)-*
M4PROJECTS_DIR ?= $(realpath STM32CubeMP1)
DEPLOY_DIR ?= $(PWD)/deploy
BUILDTOOLS_DIR ?= $(realpath build-tools)

MODE ?= trusted
#MODE ?= basic
BOARD_NAME := osd32mp1-red
KDEFCONFIG ?= osd32_defconfig

ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

NPROCS=$(shell nproc)
FLAGS=-j $(NPROCS)

SDCARD_SIZE_GB=8192
ROOTFS_EXTRA_SPACE=1024

.PHONY: setup patch_fsbl patch_ssbl patch_kernel fsbl ssbl kernel bootfs gcnano rootfs vendorfs m4_demo all clean

patch_fsbl:
	for file in $(BUILDTOOLS_DIR)/patches/$(ATF_VERSION)/*.patch; do \
		git apply --check --directory=bootloader/$(ATF_VERSION) $$file > /dev/null 2>&1; \
		if [ "$$?" -eq "0" ]; then \
			echo "Apply $$file"; \
			git apply --whitespace=nowarn --directory=bootloader/$(ATF_VERSION) $$file; \
		fi \
	done
	touch $(KERNEL_DIR)/.scmversion

patch_ssbl:
	for file in $(BUILDTOOLS_DIR)/patches/$(UBOOT_VERSION)/*.patch; do \
		git apply --check --directory=bootloader/$(UBOOT_VERSION) $$file > /dev/null 2>&1; \
		if [ "$$?" -eq "0" ]; then \
			echo "Apply $$file"; \
			git apply --whitespace=nowarn --directory=bootloader/$(UBOOT_VERSION) $$file; \
		fi \
	done
	touch $(KERNEL_DIR)/.scmversion

patch_kernel:
	for file in $(BUILDTOOLS_DIR)/patches/$(KERNEL_VERSION)/*.patch; do \
		git apply --check --directory=kernel/$(KERNEL_VERSION) $$file > /dev/null 2>&1; \
		if [ "$$?" -eq "0" ]; then \
			echo "Apply $$file"; \
			git apply --whitespace=nowarn --directory=kernel/$(KERNEL_VERSION) $$file; \
		fi \
	done
	cp $(BUILDTOOLS_DIR)/patches/$(KERNEL_VERSION)/osd32_defconfig $(KERNEL_DIR)/arch/arm/configs/
	touch $(KERNEL_DIR)/.scmversion

setup:
	mkdir -p $(DEPLOY_DIR)/bootfs
	cp $(BUILDTOOLS_DIR)/files/flash-tools/generate_tsv.sh $(DEPLOY_DIR)/
	cp $(BUILDTOOLS_DIR)/files/flash-tools/create_sdcard_from_flashlayout.sh  $(DEPLOY_DIR)/
	patch --ignore-whitespace $(DEPLOY_DIR)/create_sdcard_from_flashlayout.sh $(BUILDTOOLS_DIR)/files/flash-tools/sdcard-script.patch

# First stage bootloader
fsbl: setup patch_fsbl
	cp $(BUILDTOOLS_DIR)/files/fsbl/Makefile.sdk $(FSBL_DIR)
	
	STM32MP_SDMMC=1 PWD=$(FSBL_DIR) $(MAKE) $(FLAGS) -C $(FSBL_DIR) -f Makefile.sdk TF_A_CONFIG=$(MODE) TFA_DEVICETREE=$(BOARD_NAME) all
	cp $(FSBL_DIR)/build/$(MODE)/tf-a-$(BOARD_NAME).stm32 $(DEPLOY_DIR)
	cp $(FSBL_DIR)/build/$(MODE)/tf-a-$(BOARD_NAME)-$(MODE).stm32 $(DEPLOY_DIR)

# Second stage bootloader
ssbl: setup patch_ssbl
	cp $(BUILDTOOLS_DIR)/files/ssbl/boot.scr.cmd $(SSBL_DIR)
	$(MAKE) $(FLAGS) -C $(SSBL_DIR) stm32mp15_$(MODE)_defconfig
	$(MAKE) $(FLAGS) -C $(SSBL_DIR) DEVICE_TREE=$(BOARD_NAME) all
	$(SSBL_DIR)/tools/mkimage -C none -A arm -T script -d $(SSBL_DIR)/boot.scr.cmd $(DEPLOY_DIR)/bootfs/boot.scr.uimg
	cp $(SSBL_DIR)/u-boot.stm32 $(DEPLOY_DIR)/u-boot-$(BOARD_NAME)-$(MODE).stm32

kernel: setup patch_kernel
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) $(KDEFCONFIG)
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) $(BOARD_NAME).dtb
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR)
	mkimage -A arm -O linux -T kernel -C none -a 0xC2000040 -e 0xC2000040 -n "Linux kernel" -d $(KERNEL_DIR)/arch/arm/boot/zImage $(DEPLOY_DIR)/bootfs/uImage
	cp $(KERNEL_DIR)/arch/arm/boot/dts/$(BOARD_NAME).dtb $(DEPLOY_DIR)/bootfs

bootfs: kernel
	# Generate extlinux files
	$(BUILDTOOLS_DIR)/$(BOARD_NAME)-extlinux.sh -d $(DEPLOY_DIR)/bootfs
	
	# Copy boot files
	cp $(BUILDTOOLS_DIR)/files/bootfs/uboot.env $(DEPLOY_DIR)/bootfs/
	cp $(BUILDTOOLS_DIR)/files/bootfs/splash.bmp $(DEPLOY_DIR)/bootfs/
	
	# Format bootfs partition
	dd if=/dev/zero of=$(DEPLOY_DIR)/octavo-bootfs-debian-lxqt-$(BOARD_NAME).ext4 bs=1M count=64
	sync
	mkfs.ext4 -b 1024 -d $(DEPLOY_DIR)/bootfs -L bootfs $(DEPLOY_DIR)/octavo-bootfs-debian-lxqt-$(BOARD_NAME).ext4

gcnano: kernel
	if [ ! -d $(GCNANO_DRV_DIR)/ ]; then \
		tar xvf $(GCNANO_DIR)/gcnano-driver-*.tar.xz -C $(GCNANO_DIR); \
	fi
	AQROOT=$(GCNANO_DRV_DIR) KERNEL_DIR=$(KERNEL_DIR) $(MAKE) $(FLAGS) -C $(GCNANO_DRV_DIR)
	
	if [ ! -d $(GCNANO_USR_DIR)/ ]; then \
		cd $(GCNANO_DIR); \
		sh gcnano-userland-multi-*.bin  --auto-accept; \
		cd $(ROOT_DIR);  \
	fi

rootfs: kernel gcnano m4_demo
	$(MAKE) $(FLAGS) -C $(MULTISTRAP_DIR) all
	
	# Install kernel modules
	$(eval KRELEASE := $(shell $(MAKE) $(FLAGS) --no-print-directory -C $(KERNEL_DIR) kernelrelease))
	mkdir -p $(ROOTFS_DIR)/lib/modules/$(KRELEASE)/extra/
	cp $(GCNANO_DRV_DIR)/galcore.ko $(ROOTFS_DIR)/lib/modules/$(KRELEASE)/extra/
	INSTALL_MOD_PATH=$(ROOTFS_DIR) $(MAKE) $(FLAGS) -C $(KERNEL_DIR) modules_install
	INSTALL_MOD_PATH=$(ROOTFS_DIR) $(KERNEL_DIR)/scripts/depmod.sh /sbin/depmod $(KRELEASE)
	
	# Install firmwares
	mkdir -p $(ROOTFS_DIR)/lib/firmware/brcm/
	cp $(BUILDTOOLS_DIR)/files/firmwares/CYW43430A1.1DX.hcd $(ROOTFS_DIR)/lib/firmware/brcm/BCM43430A1.hcd
	cp $(BUILDTOOLS_DIR)/files/firmwares/LICENCE.cypress $(ROOTFS_DIR)/lib/firmware/LICENCE.cypress_bcm4343
	cp $(BUILDTOOLS_DIR)/files/firmwares/brcmfmac43430-sdio.txt $(ROOTFS_DIR)/lib/firmware/brcm/
	cp $(BUILDTOOLS_DIR)/files/firmwares/brcmfmac43430-sdio.bin $(ROOTFS_DIR)/lib/firmware/brcm/
	cp $(BUILDTOOLS_DIR)/files/firmwares/brcmfmac43430-sdio.1DX.clm_blob $(ROOTFS_DIR)/lib/firmware/brcm/brcmfmac43430-sdio.clm_blob
	
	# Install M4 files
	mkdir -p $(ROOTFS_DIR)/etc/init.d/
	mkdir -p $(ROOTFS_DIR)/sbin/
	cp $(M4PROJECTS_DIR)/st-m4firmware-load-default.sh $(ROOTFS_DIR)/etc/init.d/st-m4firmware-load-default.sh
	cp $(M4PROJECTS_DIR)/st-m4firmware-load-default.sh $(ROOTFS_DIR)/sbin/st-m4firmware-load-default.sh
	sed -i -e "s:@default_fw@:${DEFAULT_COPRO_FIRMWARE}:" $(ROOTFS_DIR)/etc/init.d/st-m4firmware-load-default.sh
	sed -i -e "s:@default_fw@:${DEFAULT_COPRO_FIRMWARE}:" $(ROOTFS_DIR)/sbin/st-m4firmware-load-default.sh
	sed -i -e "s:@userfs_mount_point@:${STM32MP_USERFS_MOUNTPOINT_IMAGE}:" $(ROOTFS_DIR)/etc/init.d/st-m4firmware-load-default.sh
	sed -i -e "s:@userfs_mount_point@:${STM32MP_USERFS_MOUNTPOINT_IMAGE}:" $(ROOTFS_DIR)/sbin/st-m4firmware-load-default.sh
	cp $(M4PROJECTS_DIR)/st-m4firmware-load.service $(ROOTFS_DIR)/lib/systemd/system/
	

 	# Install demo files
	cp $(BUILDTOOLS_DIR)/files/demo_camera.sh $(ROOTFS_DIR)/home/debian
	cp $(BUILDTOOLS_DIR)/files/demo_video.sh $(ROOTFS_DIR)/home/debian
	cp $(BUILDTOOLS_DIR)/files/OSD32MP1_RED_intro_360p.mp4 $(ROOTFS_DIR)/home/debian
	cp -R $(M4PROJECTS_DIR)/deploy/STM32MP157C-DK2 $(ROOTFS_DIR)/usr/local/bin/

	# Create image
	tar -cf $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-$(BOARD_NAME).tar -C $(ROOTFS_DIR) .
	virt-make-fs --type=ext4 --size=+$(ROOTFS_EXTRA_SPACE)M $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-$(BOARD_NAME).tar $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-$(BOARD_NAME).ext4

vendorfs: setup gcnano
	dd if=/dev/zero of=$(DEPLOY_DIR)/octavo-vendorfs-debian-lxqt-$(BOARD_NAME).ext4 bs=1M count=16
	sync
	
	# Remove things we do not need
	rm -rf $(GCNANO_USR_DIR)/usr/include
	rm -f $(GCNANO_USR_DIR)/usr/lib/*debug*
	rm -rf $(GCNANO_USR_DIR)/usr/lib/pkgconfig
	
	mkfs.ext4 -b 1024 -d $(GCNANO_USR_DIR)/usr/ -L vendorfs $(DEPLOY_DIR)/octavo-vendorfs-debian-lxqt-$(BOARD_NAME).ext4

m4_demo: setup
	if [ ! -d $(M4PROJECTS_DIR)/deploy ]; then \
		cp $(BUILDTOOLS_DIR)/files/m4projects/* $(M4PROJECTS_DIR); \
		cd $(M4PROJECTS_DIR) ; ./build_m4projects.sh; \
	fi

image:
	rm -rf $(DEPLOY_DIR)/FlashLayout_sdcard_$(BOARD_NAME)-$(MODE).raw
	$(DEPLOY_DIR)/generate_tsv.sh -b $(BOARD_NAME) -m $(MODE) -d 0
	$(DEPLOY_DIR)/generate_tsv.sh -b $(BOARD_NAME) -m $(MODE) -d 1
	$(DEPLOY_DIR)/create_sdcard_from_flashlayout.sh $(DEPLOY_DIR)/FlashLayout_sdcard_$(BOARD_NAME)-$(MODE).tsv $(SDCARD_SIZE_GB)

all: ssbl fsbl bootfs rootfs vendorfs image

fsbl_clean:
	$(MAKE) $(FLAGS) -C $(FSBL_DIR) clean
	$(MAKE) $(FLAGS) -C $(FSBL_DIR) distclean
	git --git-dir $(FSBL_DIR)/.git reset --hard HEAD
	git --git-dir $(FSBL_DIR)/.git clean -f -d

ssbl_clean:
	$(MAKE) $(FLAGS) -C $(SSBL_DIR) clean
	$(MAKE) $(FLAGS) -C $(SSBL_DIR) distclean
	git --git-dir $(SSBL_DIR)/.git reset --hard HEAD
	git --git-dir $(SSBL_DIR)/.git clean -f -d

kernel_clean:
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) clean
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) distclean
	git --git-dir $(KERNEL_DIR)/.git reset --hard HEAD
	git --git-dir $(KERNEL_DIR)/.git clean -f -d

clean: ssbl_clean fsbl_clean kernel_clean
	$(MAKE) $(FLAGS) -C $(MULTISTRAP_DIR) clean
	@rm -rf $(DEPLOY_DIR)
	@rm -rf $(ROOTFS_DIR)

