#
# SPDX-License-Identifier:	GPL-2.0+

ROOT_DIR = $(PWD)
ATF_VERSION=arm-trusted-firmware-2.4
UBOOT_VERSION = u-boot-2020.10
KERNEL_VERSION=linux-5.10
GCNANO_VERSION=6.4.3
GCNANO_SUBVERSION=20200902

FSBL_DIR ?= $(realpath bootloader/$(ATF_VERSION))
SSBL_DIR ?= $(realpath bootloader/$(UBOOT_VERSION))
KERNEL_DIR ?= $(realpath kernel/$(KERNEL_VERSION))
FIP_FWCONF_DIR ?= $(realpath bootloader/$(ATF_VERSION)/deploy/fwconfig)
FIP_TFA_DIR ?= $(realpath bootloader/$(ATF_VERSION)/deploy/bl32)
MULTISTRAP_DIR ?= $(realpath multistrap)
ROOTFS_DIR ?= $(MULTISTRAP_DIR)/multistrap-debian-bullseye
GCNANO_DIR ?= $(realpath gcnano-$(GCNANO_VERSION).binaries)
GCNANO_DRV_DIR ?= $(GCNANO_DIR)/gcnano-driver-$(GCNANO_VERSION)
GCNANO_USR_DIR ?= $(GCNANO_DIR)/gcnano-userland-multi-$(GCNANO_VERSION)-$(GCNANO_SUBVERSION)
M4PROJECTS_DIR ?= $(realpath STM32CubeMP1)
DEPLOY_DIR ?= $(PWD)/deploy
BUILDTOOLS_DIR ?= $(realpath build-tools)

MODE ?= trusted
BOARD_NAME := stm32mp157c-osd32mp1-red
KDEFCONFIG ?= multi_v7_defconfig
BOOT_EMMC = 1
BOOT_SD = 1
BOARD_RED = stm32mp157c-osd32mp1-red
BOARD_BRK = stm32mp157c-osd32mp1-brk

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
	cp $(BUILDTOOLS_DIR)/patches/$(KERNEL_VERSION)/fragment-* kernel/$(KERNEL_VERSION)/arch/arm/configs
	touch $(KERNEL_DIR)/.scmversion

setup:
	PWD=$(FSBL_DIR)/tools/fiptool $(MAKE) -C $(FSBL_DIR)/tools/fiptool
	cp $(FSBL_DIR)/tools/fiptool/fiptool /bin/
	cp $(BUILDTOOLS_DIR)/files/fsbl/fiptool-stm32mp /bin/
	mkdir -p $(DEPLOY_DIR)/bootfs
	cp $(BUILDTOOLS_DIR)/files/flash-tools/generate_tsv.sh $(DEPLOY_DIR)/
	cp $(BUILDTOOLS_DIR)/files/flash-tools/create_sdcard_from_flashlayout.sh  $(DEPLOY_DIR)/
	patch --ignore-whitespace $(DEPLOY_DIR)/create_sdcard_from_flashlayout.sh $(BUILDTOOLS_DIR)/files/flash-tools/sdcard-script.patch

# First stage bootloader
# Add to if statement for custom board
fsbl: setup patch_fsbl
	cp $(BUILDTOOLS_DIR)/files/fsbl/Makefile.sdk $(FSBL_DIR)
	PWD=$(FSBL_DIR) $(MAKE) $(FLAGS) -C $(FSBL_DIR) -f Makefile.sdk stm32
	cp $(FSBL_DIR)/deploy/tf-a-$(BOARD_NAME)-usb.stm32 $(DEPLOY_DIR)
	if [ "$(BOOT_SD)" -eq "1" ]; then \
		cp $(FSBL_DIR)/deploy/tf-a-$(BOARD_NAME)-sdcard.stm32 $(DEPLOY_DIR); \
	fi
	if [ "$(BOOT_EMMC)" -eq "1" ]; then \
		cp $(FSBL_DIR)/deploy/tf-a-$(BOARD_NAME)-emmc.stm32 $(DEPLOY_DIR); \
	fi


# Second stage bootloader
ssbl: setup fsbl patch_ssbl
	cp $(BUILDTOOLS_DIR)/files/ssbl/boot.scr.cmd $(SSBL_DIR)
	cp $(BUILDTOOLS_DIR)/files/ssbl/Makefile.sdk $(SSBL_DIR)
	PWD=$(SSBL_DIR) FIP_DEPLOYDIR_FIP=$(DEPLOY_DIR) FIP_DEPLOYDIR_TFA=$(FIP_TFA_DIR) FIP_DEPLOYDIR_FWCONF=$(FIP_FWCONF_DIR) $(MAKE) $(FLAGS) -C $(SSBL_DIR) -f Makefile.sdk all UBOOT_CONFIG=trusted UBOOT_DEFCONFIG=stm32mp15_trusted_defconfig UBOOT_BINARY=u-boot.dtb FIP_CONFIG="trusted" FIP_BL32_CONF="tfa," DEVICETREE=$(BOARD_NAME)
	

kernel: setup patch_kernel
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) $(KDEFCONFIG) fragment*.config
	yes '' | $(MAKE) -C $(KERNEL_DIR) oldconfig
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) $(BOARD_NAME).dtb
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR)
	mkimage -A arm -O linux -T kernel -C none -a 0xC2000040 -e 0xC2000040 -n "Linux kernel" -d $(KERNEL_DIR)/arch/arm/boot/zImage $(DEPLOY_DIR)/bootfs/uImage
	cp $(KERNEL_DIR)/arch/arm/boot/dts/$(BOARD_NAME).dtb $(DEPLOY_DIR)/bootfs

bootfs: kernel
	# Generate extlinux files
	$(BUILDTOOLS_DIR)/$(BOARD_NAME)-extlinux.sh -d $(DEPLOY_DIR)/bootfs
	
	# Copy boot files
	cp $(BUILDTOOLS_DIR)/files/bootfs/boot.scr.uimg $(DEPLOY_DIR)/bootfs/
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

	# Signing out of tree galcore module
	$(KERNEL_DIR)/scripts/sign-file sha256 $(KERNEL_DIR)/certs/signing_key.pem $(KERNEL_DIR)/certs/signing_key.x509 $(GCNANO_DRV_DIR)/galcore.ko

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
	cp $(BUILDTOOLS_DIR)/files/firmwares/brcmfmac43430-sdio.txt $(ROOTFS_DIR)/lib/firmware/brcm/brcmfmac43430-sdio.octavo,stm32mp157c-osd32mp1-red.txt
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

 	# Install demo files for OSD32MP1-RED
ifeq ($(BOARD_NAME), $(BOARD_RED))
	cp $(BUILDTOOLS_DIR)/files/demo_red/demo_camera.sh $(ROOTFS_DIR)/home/debian; \
	cp $(BUILDTOOLS_DIR)/files/demo_red/demo_video.sh $(ROOTFS_DIR)/home/debian; \
	cp $(BUILDTOOLS_DIR)/files/demo_red/OSD32MP1_RED_intro_360p.mp4 $(ROOTFS_DIR)/home/debian;
endif

	# Instll demo files for OSD32MP1-BRK
ifeq ($(BOARD_NAME), $(BOARD_BRK))
	mkdir -p $(ROOTFS_DIR)/usr/local/demo/; \
	cp -R $(BUILDTOOLS_DIR)/files/demo_brk/LEDWebDemo/ $(ROOTFS_DIR)/usr/local/demo/;
endif

	# Install M4 demo firmware
	cp -R $(M4PROJECTS_DIR)/deploy/STM32MP157C-DK2 $(ROOTFS_DIR)/usr/local/bin/

	if [ $(BOOT_EMMC) -eq 1 ]; then \
		cp $(BUILDTOOLS_DIR)/files/rootfs/fstab_emmc_$(BOARD_NAME) $(ROOTFS_DIR)/etc/fstab; \
		tar -cf $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-emmc-$(BOARD_NAME).tar -C $(ROOTFS_DIR) .; \
		virt-make-fs --type=ext4 --size=+$(ROOTFS_EXTRA_SPACE)M $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-emmc-$(BOARD_NAME).tar $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-emmc-$(BOARD_NAME).ext4; \
	fi

	if [ $(BOOT_SD) -eq 1 ]; then \
		cp $(BUILDTOOLS_DIR)/files/rootfs/fstab_sdcard_$(BOARD_NAME) $(ROOTFS_DIR)/etc/fstab; \
		tar -cf $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-sdcard-$(BOARD_NAME).tar -C $(ROOTFS_DIR) .; \
		virt-make-fs --type=ext4 --size=+$(ROOTFS_EXTRA_SPACE)M $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-sdcard-$(BOARD_NAME).tar $(DEPLOY_DIR)/octavo-rootfs-debian-lxqt-sdcard-$(BOARD_NAME).ext4; \
	fi





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

image: fsbl ssbl bootfs rootfs vendorfs
	if [ $(BOOT_SD) -eq 1 ]; then \
		$(DEPLOY_DIR)/generate_tsv.sh -b $(BOARD_NAME) -m $(MODE) -d 0; \
		$(DEPLOY_DIR)/create_sdcard_from_flashlayout.sh $(DEPLOY_DIR)/FlashLayout_sdcard_$(BOARD_NAME)-$(MODE).tsv $(SDCARD_SIZE_GB); \
	fi
	if [ $(BOOT_EMMC) -eq 1 ]; then \
		$(DEPLOY_DIR)/generate_tsv.sh -b $(BOARD_NAME) -m $(MODE) -d 1; \
	fi

all: ssbl fsbl bootfs rootfs vendorfs image

fsbl_clean:
	$(MAKE) $(FLAGS) -C $(FSBL_DIR) clean
	$(MAKE) $(FLAGS) -C $(FSBL_DIR) distclean
	git --git-dir=$(FSBL_DIR)/.git --work-tree=$(FSBL_DIR) reset --hard HEAD
	git --git-dir=$(FSBL_DIR)/.git --work-tree=$(FSBL_DIR) clean -f -d

ssbl_clean:
	$(MAKE) $(FLAGS) -C $(SSBL_DIR) clean
	$(MAKE) $(FLAGS) -C $(SSBL_DIR) distclean
	git --git-dir=$(SSBL_DIR)/.git --work-tree=$(SSBL_DIR) reset --hard HEAD
	git --git-dir=$(SSBL_DIR)/.git --work-tree=$(SSBL_DIR) clean -f -d

kernel_clean:
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) clean
	$(MAKE) $(FLAGS) -C $(KERNEL_DIR) distclean
	git --git-dir=$(KERNEL_DIR)/.git --work-tree=$(KERNEL_DIR) reset --hard HEAD
	git --git-dir=$(KERNEL_DIR)/.git --work-tree=$(KERNEL_DIR) clean -f -d

clean: ssbl_clean fsbl_clean kernel_clean
	$(MAKE) $(FLAGS) -C $(MULTISTRAP_DIR) clean
	@rm -rf $(GCNANO_DRV_DIR)
	@rm -rf $(GCNANO_DRV_DIR)/galcore.ko
	@rm -rf $(DEPLOY_DIR)
	@rm -rf $(ROOTFS_DIR)
	@rm -rf $(GCNANO_USR_DIR)

