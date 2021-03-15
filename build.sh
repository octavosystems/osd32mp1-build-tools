#!/bin/bash -e

#`dirname "$0"`/../
ROOT_DIR=${PWD}/
OCTAVO_REV=master
DEPLOY_DIR=${ROOT_DIR}/deploy/

# Mode can be: 'basic', 'trusted' or 'optee'
MODE=trusted
BOARD_NAME=osd32mp1-red
KCONFIG=stm32mp_defconfig

#./tools/mkimage -C none -A arm -T script -d boot.src.cmd boot.scr.uimg

setup_build_environment () {

    echo "DIR name `dirname "$0"`"
    echo "PWD name ${PWD}"

    export ARCH=arm
    export CROSS_COMPILE=arm-linux-gnueabihf-
    mkdir -p ${ROOT_DIR}/deploy/bootfs

    cp ${ROOT_DIR}/build-tools/files/create_sdcard_from_flashlayout.sh ${DEPLOY_DIR}/
    cp ${ROOT_DIR}/build-tools/files/FlashLayout_sdcard_${BOARD_NAME}-${MODE}.tsv ${DEPLOY_DIR}/

    cp ${ROOT_DIR}/build-tools/st-tools/boot.scr.cmd ${ROOT_DIR}/bootloader/u-boot-2018.11/
    #cp ${ROOT_DIR}/build-tools/files/uboot-env.txt ${ROOT_DIR}/bootloader/u-boot-2018.11/

    cp ${ROOT_DIR}/build-tools/files/uboot.env ${DEPLOY_DIR}/bootfs/
    cp ${ROOT_DIR}/build-tools/files/splash.bmp ${DEPLOY_DIR}/bootfs/
    cp -R ${ROOT_DIR}/build-tools/files/mmc0_${BOARD_NAME}_extlinux ${DEPLOY_DIR}/bootfs/

    cp ${ROOT_DIR}/build-tools/st-tools/Makefile.sdk ${ROOT_DIR}/bootloader/arm-trusted-firmware-2.0/
}

build_deploy_m4_demo() {

    cd ${ROOT_DIR}/STM32CubeMP1/
    cp ${ROOT_DIR}/build-tools/files/m4projects/* .

    export PROJECTS_LIST_DK2=" \
	STM32MP157C-DK2/Examples/ADC/ADC_SingleConversion_TriggerTimer_DMA \
	STM32MP157C-DK2/Examples/Cortex/CORTEXM_MPU \
	STM32MP157C-DK2/Examples/CRC/CRC_UserDefinedPolynomial \
	STM32MP157C-DK2/Examples/CRYP/CRYP_AES_DMA \
	STM32MP157C-DK2/Examples/DMA/DMA_FIFOMode \
	STM32MP157C-DK2/Examples/GPIO/GPIO_EXTI \
	STM32MP157C-DK2/Examples/HASH/HASH_SHA224SHA256_DMA \
	STM32MP157C-DK2/Examples/I2C/I2C_TwoBoards_ComIT \
	STM32MP157C-DK2/Examples/LPTIM/LPTIM_PulseCounter \
	STM32MP157C-DK2/Examples/PWR/PWR_STOP_CoPro \
	STM32MP157C-DK2/Examples/SPI/SPI_FullDuplex_ComDMA_Master \
	STM32MP157C-DK2/Examples/SPI/SPI_FullDuplex_ComDMA_Slave \
	STM32MP157C-DK2/Examples/SPI/SPI_FullDuplex_ComIT_Master \
	STM32MP157C-DK2/Examples/SPI/SPI_FullDuplex_ComIT_Slave \
	STM32MP157C-DK2/Examples/TIM/TIM_DMABurst \
	STM32MP157C-DK2/Examples/UART/UART_TwoBoards_ComDMA \
	STM32MP157C-DK2/Examples/UART/UART_TwoBoards_ComIT \
	STM32MP157C-DK2/Examples/UART/UART_Receive_Transmit_Console \
	STM32MP157C-DK2/Examples/WWDG/WWDG_Example \
	STM32MP157C-DK2/Applications/OpenAMP/OpenAMP_raw \
	STM32MP157C-DK2/Applications/OpenAMP/OpenAMP_TTY_echo \
	STM32MP157C-DK2/Applications/OpenAMP/OpenAMP_TTY_echo_wakeup \
	STM32MP157C-DK2/Applications/FreeRTOS/FreeRTOS_ThreadCreation \
	STM32MP157C-DK2/Applications/CoproSync/CoproSync_ShutDown \
	STM32MP157C-DK2/Demonstrations/AI_Character_Recognition \
"

    export PROJECTS_LIST="${PROJECTS_LIST_DK2}"
    export MACHINE=STM32MP157C-DK2
    export CPU_TYPE="M4"
    export BUILD_CONFIG="Debug"


    for project in ${PROJECTS_LIST} ; do
        echo "Parsing M4 project : ${project}"

        if [ "$(echo ${project} | cut -d'/' -f1)" = "${MACHINE}" ]; then
            echo "Selected M4 project : ${project}"

            unset LDFLAGS CFLAGS CPPFLAGS CFLAGS_ASM
            # Export variables as used by Makefile
            export BIN_NAME=$(basename ${project})
            export PROJECT_DIR=${PWD}/build/${project}
            export PROJECT_APP="${PWD}/Projects/${project}/SW4STM32/${BIN_NAME}"

            echo "BIN_NAME     : ${BIN_NAME}"
            echo "PROJECT_DIR  : ${PROJECT_DIR}"
            echo "PROJECT_APP  : ${PROJECT_APP}"
            echo "BUILD_CONFIG : ${BUILD_CONFIG}"
            echo "CPU_TYPE     : ${CPU_TYPE}"
            echo "SOURCE       : ${PWD}"

            mkdir -p ${PROJECT_DIR}/out/${BUILD_CONFIG}

            # parse project to get file list and build flags
            python ${PWD}/parse_project_config.py ${PROJECT_APP} ${BUILD_CONFIG} ${PROJECT_DIR}

            # make clean
            echo "Cleaning M4 project : ${project}"
            CROSS_COMPILE=arm-none-eabi- make -f ${PWD}/Makefile.stm32 clean

            # make build
            echo "Building M4 project : ${project}"
            CROSS_COMPILE=arm-none-eabi- make -f ${PWD}/Makefile.stm32 all
        fi
    done

    for project in ${PROJECTS_LIST} ; do
        if [ "$(echo ${project} | cut -d'/' -f1)" = "${MACHINE}" ]; then
            BIN_NAME=$(basename ${project})

            # Install M4 firmwares
            export USER_FS=${DEPLOY_DIR}/userfs/Cube-M4-examples/
            mkdir -p ${USER_FS}/${project}/lib/firmware/
            cp ${PWD}/build/${project}/out/${BUILD_CONFIG}/${BIN_NAME}.elf ${USER_FS}/${project}/lib/firmware/

            # Install sh and README files if any for each example
            if [ -e ${S}/Projects/${project}/Remoteproc/fw_cortex_m4.sh ]; then
                cp ${S}/Projects/${project}/Remoteproc/fw_cortex_m4.sh ${USER_FS}/${project}
             fi
             if [ -e ${S}/Projects/${project}/Remoteproc/README ]; then
                 cp ${S}/Projects/${project}/Remoteproc/README ${USER_FS}/${project}
             fi
        fi
    done

    #Install systemd service
    mkdir -p ${ROOT_DIR}/multistrap/multistrap-debian-buster/etc/init.d/
    mkdir -p ${ROOT_DIR}/multistrap/multistrap-debian-buster/sbin/
    cp ${PWD}/st-m4firmware-load-default.sh ${ROOT_DIR}/multistrap/multistrap-debian-buster/etc/init.d/st-m4firmware-load-default.sh
    cp ${PWD}/st-m4firmware-load-default.sh ${ROOT_DIR}/multistrap/multistrap-debian-buster/sbin/st-m4firmware-load-default.sh

    sed -i -e "s:@default_fw@:${DEFAULT_COPRO_FIRMWARE}:" \
    ${ROOT_DIR}/multistrap/multistrap-debian-buster/etc/init.d/st-m4firmware-load-default.sh
    sed -i -e "s:@default_fw@:${DEFAULT_COPRO_FIRMWARE}:" \
    ${ROOT_DIR}/multistrap/multistrap-debian-buster/sbin/st-m4firmware-load-default.sh

    sed -i -e "s:@userfs_mount_point@:${STM32MP_USERFS_MOUNTPOINT_IMAGE}:" \
    ${ROOT_DIR}/multistrap/multistrap-debian-buster/etc/init.d/st-m4firmware-load-default.sh
    sed -i -e "s:@userfs_mount_point@:${STM32MP_USERFS_MOUNTPOINT_IMAGE}:" \
    ${ROOT_DIR}/multistrap/multistrap-debian-buster/sbin/st-m4firmware-load-default.sh


    # install systemd service for all machines configurations
    mkdir -p ${ROOT_DIR}/multistrap/multistrap-debian-buster/lib/systemd/system/
    cp ${PWD}/st-m4firmware-load.service ${ROOT_DIR}/multistrap/multistrap-debian-buster/lib/systemd/system/
}

build_deploy_bootloader () {

    # Build and deploy TF-A
    cd ${ROOT_DIR}/bootloader/arm-trusted-firmware-2.0/

    STM32MP_SDMMC=1 make -j$(nproc) -f Makefile.sdk TF_A_CONFIG=${MODE} TFA_DEVICETREE=${BOARD_NAME} all
    cp ./build/${MODE}/tf-a-${BOARD_NAME}.stm32 ${DEPLOY_DIR}
    cp ./build/${MODE}/tf-a-${BOARD_NAME}-${MODE}.stm32 ${DEPLOY_DIR}

    # Build and deploy u-boot
    cd ${ROOT_DIR}/bootloader/u-boot-2018.11/
    make -j$(nproc) stm32mp15_${MODE}_defconfig
    make -j$(nproc) DEVICE_TREE=${BOARD_NAME} all
    ./tools/mkimage -C none -A arm -T script -d boot.scr.cmd boot.scr.uimg
    #./tools/mkenvimage -s 0x2000 -o uboot.env uboot-env.txt

    cp u-boot.stm32 ${DEPLOY_DIR}/u-boot-${BOARD_NAME}-${MODE}.stm32
    cp boot.scr.uimg ${DEPLOY_DIR}/bootfs/
    #cp uboot.env ${DEPLOY_DIR}/bootfs/
}

build_deploy_bootfs () {

    # Build and deploy kernel
    cd ${ROOT_DIR}/kernel/linux-4.19.49/
    if [ ! -f ".config" ]; then
        make -j$(nproc) defconfig ${KCONFIG}
    fi
    make -j$(nproc) ${BOARD_NAME}.dtb
    make -j$(nproc)
    mkimage -A arm -O linux -T kernel -C none -a 0xC2000040 -e 0xC2000040 -n "Linux kernel" -d arch/arm/boot/zImage uImage

    export KRELEASE=`make kernelrelease`

    cp uImage ${DEPLOY_DIR}/bootfs
    cp arch/arm/boot/dts/${BOARD_NAME}.dtb ${DEPLOY_DIR}/bootfs

    # Create and populate bootfs partion
    dd if=/dev/zero of=${DEPLOY_DIR}/octavo-bootfs-debian-lxqt-${BOARD_NAME}.ext4 bs=1M count=64
    sync
    mkfs.ext4 -b 1024 -d ${DEPLOY_DIR}/bootfs -L bootfs ${DEPLOY_DIR}/octavo-bootfs-debian-lxqt-${BOARD_NAME}.ext4
}

build_deploy_rootfs () {

    echo "[OCTAVO] Multistrap START!"
    cd ${ROOT_DIR}/multistrap/
    rm -f multistrap-debian-buster/var/lib/dpkg/status
    multistrap --file debian-config-buster -d multistrap-debian-buster
    echo "[OCTAVO] Multistrap DONE!"

    echo "[OCTAVO] Install user files!"
    cp -R files/* multistrap-debian-buster/
    echo "[OCTAVO] User files installation DONE!"

    cp /usr/bin/qemu-arm-static multistrap-debian-buster/usr/bin
    #sh -c "echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:' > /proc/sys/fs/binfmt_misc/register"

    echo "[OCTAVO] Configuring rootfs..."
    chroot multistrap-debian-buster/ ./multistrap.configscript
    echo "[OCTAVO] Rootfs configured!"

    echo "[OCTAVO] Install kernel modules"
    cd ${ROOT_DIR}/gcnano-6.2.4_p4-binaries/
    if [ ! -d gcnano-driver-6.2.4.p4/ ]; then
        tar xvf gcnano-driver-6.2.4.p4.tar.xz
    fi
    cd gcnano-driver-6.2.4.p4/

    export ROOTFS_DIR=${ROOT_DIR}/multistrap/multistrap-debian-buster/

    AQROOT=${PWD} KERNEL_DIR=${ROOT_DIR}/kernel/linux-4.19.49/ make -j$(nproc)
    mkdir -p ${ROOTFS_DIR}/lib/modules/${KRELEASE}/extra/
    cp galcore.ko ${ROOTFS_DIR}/lib/modules/${KRELEASE}/extra/

    cd ${ROOT_DIR}/kernel/linux-4.19.49/
    INSTALL_MOD_PATH=${ROOTFS_DIR} make -j$(nproc) modules_install
    INSTALL_MOD_PATH=${ROOTFS_DIR} ./scripts/depmod.sh /sbin/depmod ${KRELEASE}
    cd ${ROOT_DIR}/multistrap/
    echo "[OCTAVO] Kernel modules installation DONE!"

    echo "[OCTAVO] Install firmwares"
    mkdir -p ${ROOTFS_DIR}/lib/firmware/brcm/
    cp ${ROOT_DIR}/build-tools/files/firmwares/CYW43430A1.1DX.hcd ${ROOTFS_DIR}/lib/firmware/brcm/BCM43430A1.hcd
    cp ${ROOT_DIR}/build-tools/files/firmwares/LICENCE.cypress ${ROOTFS_DIR}/lib/firmware/LICENCE.cypress_bcm4343
    cp ${ROOT_DIR}/build-tools/files/firmwares/brcmfmac43430-sdio.txt ${ROOTFS_DIR}/lib/firmware/brcm/
    cp ${ROOT_DIR}/build-tools/files/firmwares/brcmfmac43430-sdio.bin ${ROOTFS_DIR}/lib/firmware/brcm/
    cp ${ROOT_DIR}/build-tools/files/firmwares/brcmfmac43430-sdio.1DX.clm_blob ${ROOTFS_DIR}/lib/firmware/brcm/brcmfmac43430-sdio.clm_blob
    echo "[OCTAVO] Firmware installation DONE!"

    echo "[OCTAVO] Flashing rootfs..."
    dd if=/dev/zero of=${DEPLOY_DIR}/octavo-rootfs-debian-lxqt-${BOARD_NAME}.ext4 bs=1M count=3072
    sync
    mkfs.ext4 -b 1024 -d multistrap-debian-buster -L rootfs ${DEPLOY_DIR}/octavo-rootfs-debian-lxqt-${BOARD_NAME}.ext4
    echo "[OCTAVO] Rootfs flashed!"
}

build_deploy_vendorfs () {
    cd ${ROOT_DIR}/gcnano-6.2.4_p4-binaries/

    if [ ! -d gcnano-userland-multi-6.2.4.p4-20190626/ ]; then
        sh gcnano-userland-multi-6.2.4.p4-20190626.bin  --auto-accept
    fi

    dd if=/dev/zero of=${DEPLOY_DIR}/octavo-vendorfs-debian-lxqt-${BOARD_NAME}.ext4 bs=1M count=16
    sync

    # Remove things we do not need
    rm -rf gcnano-userland-multi-6.2.4.p4-20190626/usr/include
    rm -f gcnano-userland-multi-6.2.4.p4-20190626/usr/lib/*debug*
    rm -rf gcnano-userland-multi-6.2.4.p4-20190626/usr/lib/pkgconfig

    mkfs.ext4 -b 1024 -d gcnano-userland-multi-6.2.4.p4-20190626/usr/ -L vendorfs ${DEPLOY_DIR}/octavo-vendorfs-debian-lxqt-${BOARD_NAME}.ext4
}

build_raw_image () {
    cd ${DEPLOY_DIR}
    rm -rf FlashLayout_sdcard_${BOARD_NAME}-${MODE}.raw
    ./create_sdcard_from_flashlayout.sh FlashLayout_sdcard_${BOARD_NAME}-${MODE}.tsv
}

build_deploy_userfs() {
    build_deploy_m4_demo

    # Untar demo binaries
    tar xvzf ${ROOT_DIR}/build-tools/st-tools/demo.tar.gz -C ${DEPLOY_DIR}/userfs/

    dd if=/dev/zero of=${DEPLOY_DIR}/octavo-userfs-debian-lxqt-${BOARD_NAME}.ext4 bs=1M count=1024
    sync

    mkfs.ext4 -b 1024 -d ${DEPLOY_DIR}/userfs/ -L userfs ${DEPLOY_DIR}/octavo-userfs-debian-lxqt-${BOARD_NAME}.ext4
}

setup_build_environment
build_deploy_bootloader
build_deploy_bootfs
build_deploy_vendorfs
build_deploy_rootfs
build_deploy_userfs
build_raw_image

