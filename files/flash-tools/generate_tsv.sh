#!/bin/sh

SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`

while getopts b:m:d: flag
do
	case "${flag}" in
		b) BOARD_NAME=${OPTARG};;
		m) MODE=${OPTARG};;
		d) MMC_DEVICE=${OPTARG};;
	esac
done

if [ ! "$BOARD_NAME" ] || [ ! "$MODE" ] || [ ! "$MMC_DEVICE" ]
then
    echo "Missing argument..."
    exit 1
fi

FSBL1_BOOT_OFF=0x0
FSBL1_BOOT_NAME=tf-a-${BOARD_NAME}.stm32
SSBL_BOOT_OFF=0x0
SSBL_BOOT_NAME=u-boot-${BOARD_NAME}-${MODE}.stm32
FSBL_NAME=tf-a-${BOARD_NAME}.stm32
SSBL_NAME=u-boot-${BOARD_NAME}-${MODE}.stm32
BOOTFS_NAME=octavo-bootfs-debian-lxqt-${BOARD_NAME}.ext4
VENDORFS_NAME=octavo-vendorfs-debian-lxqt-${BOARD_NAME}.ext4
ROOTFS_NAME=octavo-rootfs-debian-lxqt-${BOARD_NAME}.ext4

VENDORFS_SIZE=$(du -s -b ${SCRIPTPATH}/${VENDORFS_NAME}  | awk '{print $1;}')
ROOTFS_SIZE=$(du -s -b ${SCRIPTPATH}/${ROOTFS_NAME}  | awk '{print $1;}')


if [ "${MMC_DEVICE}" = "0" ]
then
	FSBL1_OFF=0x00004400
	FSBL2_OFF=0x00044400
	SSBL_OFF=0x00084400
	BOOTFS_OFF=0x00284400
	VENDORFS_OFF=0x04284400
	ROOTFS_OFF=`printf "0x%08x" $((${VENDORFS_SIZE} + ${VENDORFS_OFF}))`
	TSV_FILE="${SCRIPTPATH}/FlashLayout_sdcard_${BOARD_NAME}-${MODE}.tsv"
elif [ "${MMC_DEVICE}" = "1" ]
then
	FSBL1_OFF=boot1
	FSBL2_OFF=boot2
	SSBL_OFF=0x00080000
	BOOTFS_OFF=0x00280000
	VENDORFS_OFF=0x04280000
	ROOTFS_OFF=`printf "0x%08x" $((${VENDORFS_SIZE} + ${VENDORFS_OFF}))`
	TSV_FILE="${SCRIPTPATH}/FlashLayout_emmc_${BOARD_NAME}-${MODE}.tsv"
else
	echo "Wrong MMC_DEVICE"
	exit 1
fi

cat <<EOF > ${TSV_FILE}
#Opt	Id	Name	Type	IP	Offset	Binary
-	0x01	fsbl1-boot	Binary	none	${FSBL1_BOOT_OFF}	${FSBL1_BOOT_NAME}
-	0x03	ssbl-boot	Binary	none	${SSBL_BOOT_OFF}	${SSBL_BOOT_NAME}
P	0x04	fsbl1	Binary	mmc${MMC_DEVICE}	${FSBL1_OFF}	${FSBL_NAME}
P	0x05	fsbl2	Binary	mmc${MMC_DEVICE}	${FSBL2_OFF}	${FSBL_NAME}
P	0x06	ssbl	Binary	mmc${MMC_DEVICE}	${SSBL_OFF}	${SSBL_NAME}
P	0x21	bootfs	System	mmc${MMC_DEVICE}	${BOOTFS_OFF}	${BOOTFS_NAME}
P	0x22	vendorfs	FileSystem	mmc${MMC_DEVICE}	${VENDORFS_OFF}	${VENDORFS_NAME}
P	0x23	rootfs	FileSystem	mmc${MMC_DEVICE}	${ROOTFS_OFF}	${ROOTFS_NAME}
EOF
