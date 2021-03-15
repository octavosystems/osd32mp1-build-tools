#!/bin/bash -e

M4_SCRIPT=$(readlink -f $0)
M4_PATH="`dirname \"${M4_SCRIPT}\"`"

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
        export PROJECT_DIR=${M4_PATH}/build/${project}
        export PROJECT_APP="${M4_PATH}/Projects/${project}/SW4STM32/${BIN_NAME}"

        echo "BIN_NAME     : ${BIN_NAME}"
        echo "PROJECT_DIR  : ${PROJECT_DIR}"
        echo "PROJECT_APP  : ${PROJECT_APP}"
        echo "BUILD_CONFIG : ${BUILD_CONFIG}"
        echo "CPU_TYPE     : ${CPU_TYPE}"
        echo "SOURCE       : ${M4_PATH}"

        mkdir -p ${PROJECT_DIR}/out/${BUILD_CONFIG}

        # parse project to get file list and build flags
        python ${PWD}/parse_project_config.py ${PROJECT_APP} ${BUILD_CONFIG} ${PROJECT_DIR}

        # make clean
        echo "Cleaning M4 project : ${project}"
        CROSS_COMPILE=arm-none-eabi- make -f ${M4_PATH}/Makefile.stm32 clean

        # make build
        echo "Building M4 project : ${project}"
        CROSS_COMPILE=arm-none-eabi- make -f ${M4_PATH}/Makefile.stm32 all
    fi
done

for project in ${PROJECTS_LIST} ; do
    if [ "$(echo ${project} | cut -d'/' -f1)" = "${MACHINE}" ]; then
        BIN_NAME=$(basename ${project})

        # Install M4 firmwares
        export DEPLOY_DIR=${M4_PATH}/deploy
        mkdir -p ${DEPLOY_DIR}/${project}/lib/firmware/
        cp ${PWD}/build/${project}/out/${BUILD_CONFIG}/${BIN_NAME}.elf ${DEPLOY_DIR}/${project}/lib/firmware/

        # Install sh and README files if any for each example
        if [ -e ${S}/Projects/${project}/Remoteproc/fw_cortex_m4.sh ]; then
            cp ${S}/Projects/${project}/Remoteproc/fw_cortex_m4.sh ${DEPLOY_DIR}/${project}
        fi
        if [ -e ${S}/Projects/${project}/Remoteproc/README ]; then
            cp ${S}/Projects/${project}/Remoteproc/README ${DEPLOY_DIR}/${project}
        fi
    fi
done
