#!/bin/bash
DEVICECONFIG=""
MENU_RESPONSE="0."
ARCH="arm64"
CUR_DIR=$PWD
OUT="$CUR_DIR/out"
LOGS="$CUR_DIR/logs"
BUILD="$CUR_DIR/build"
THREADS="$(expr $(nproc) + 1)"

export ARCH=$ARCH && export SUBARCH=$ARCH
export PATH="$CUR_DIR/assets/crosscompile/bin/:$PATH"
export CROSS_COMPILE="aarch64-linux-android-"
export DTC_EXT=/usr/bin/dtc


mkdir -p $OUT $LOGS $BUILD
mkdir -p $BUILD/modules $BUILD/dtb $BUILD/dtbo 

# Checa se o whiptail tá instalado
echo "Checking for whiptail"
if !( command -v whiptail &> /dev/null)
then
    echo "Whiptail not installed"
    exit
fi
echo "Checking for dtc"
if !( command -v dtc &> /dev/null)
then
    echo "DTC not installed"
    exit
fi

echo "Checking for ccache"
if ( command -v ccache &> /dev/null)
then
    echo "CCACHE found"
    export CROSS_COMPILE="ccache $CROSS_COMPILE"
fi

# Main menu
MENU_HEIGHT=25
MENU_WIDTH=75
LIST_SIZE=10

configmenu()
{
    if [ -z "$(ls -A kernel/ )" ]
    then
        whiptail --title "Select Device Configuration" --msgbox "Kernel not found. Please clone the kernel source code to kernel directory" 8 78
        return 0
    fi

    if [ -z "$(ls -A kernel/arch/$ARCH/configs/ )" ]
    then
        whiptail --title "Select Device Configuration" --msgbox "No config file found for arch $ARCH" 7 39
        return 0
    fi

    CONFIGS=""

    # Get all configs on arch dir
    for i in $(ls -p kernel/arch/arm64/configs/ | grep -v /) 
    do 
        CONFIGS="$CONFIGS $i '' OFF" 
    done

    DEVICECONFIG=$(whiptail --title "Select Device Configuration" --radiolist "Avaliable Config Files for arch $ARCH" $MENU_HEIGHT $MENU_WIDTH $LIST_SIZE $CONFIGS 3>&1 1>&2 2>&3)
    
    if [ "$DEVICECONFIG" != "" ]
    then
        start=`date +%s`
        {
            cd kernel        
            echo 33
            make O=$OUT -j $THREADS $DEVICECONFIG &> $LOGS/config.txt
            echo 66
            cd $CUR_DIR
            echo 100
        } | whiptail --gauge "Running make -j$THREADS xconfig" 6 50 0
        end=`date +%s`

        whiptail --title "Command completed in $((end-start)) s" --msgbox "$(tail $LOGS/config.txt)" --scrolltext $MENU_HEIGHT $MENU_WIDTH
    fi
}

xconfigmenu() {
    if [ "$DEVICECONFIG" == "" ]
    then
        whiptail --title "Configure kernel" --msgbox "Select device configuration" 7 31
        return 0
    fi

    {
        cd kernel
        make O=$OUT -j $THREADS xconfig &> $LOGS/xconfig.txt 
        cd $CUR_DIR
 
        DEVICECONFIG="$DEVICECONFIG (Modded)"
    } | whiptail --gauge "Running make -j $THREADS xconfig" 6 50 0
}

threadsmenu() {
    RESPONSE=$(whiptail --title "Change thread number" --inputbox "" 8 39 3>&1 1>&2 2>&3)
    THREADS=$RESPONSE
}

buildkernel() {
    if [ "$DEVICECONFIG" == "" ]
    then
        whiptail --title "Configure kernel" --msgbox "Select device configuration" 7 31
        return 0
    fi

    start=`date +%s`
    {
        cd kernel
        echo 25
        make O=$OUT -j $THREADS Image.gz &>$LOGS/kernel.txt | tee $LOGS/kernel.txt 
        echo 50
        cd $CUR_DIR
        echo 100
    } | whiptail --gauge "Running make -j $THREADS Image.gz" 6 50 0
    end=`date +%s`


    if [ -ne $OUT/arch/$ARCH/boot/Image.gz ]
    then
        whiptail --title "Kernel Build Failed in $((end-start)) s" --msgbox "$(tail $LOGS/kernel.txt)" --scrolltext $MENU_HEIGHT $MENU_WIDTH
        return 0
    fi

    cp $OUT/arch/$ARCH/boot/Image.gz $BUILD/Image.gz
    whiptail --title "Kernel Build Complete in $((end-start)) s" --msgbox "$(tail $LOGS/kernel.txt)" --scrolltext $MENU_HEIGHT $MENU_WIDTH
}

buildmodules() {
    if [ "$DEVICECONFIG" == "" ]
    then
        whiptail --title "Configure kernel" --msgbox "Select device configuration" 7 31
        return 0
    fi

    start=`date +%s`
    {

        # Build modules
        cd kernel        
        make O=$OUT -j $THREADS modules &>$LOGS/modules.txt | tee $LOGS/modules.txt         
        cd $CUR_DIR
        echo 50
        
        # Find all modules and move to $BUILD/modules
        find $OUT -name '*.ko' -exec cp "{}" $BUILD/modules/ \;
        echo 100

    } | whiptail --gauge "Running make -j $THREADS modules" 6 50 0
    end=`date +%s`

    
    whiptail --title "Modules Build Complete in $((end-start)) s" --msgbox "$(tail $LOGS/modules.txt)" --scrolltext $MENU_HEIGHT $MENU_WIDTH
}

builddtb() {
    if [ "$DEVICECONFIG" == "" ]
    then
        whiptail --title "Configure kernel" --msgbox "Select device configuration" 7 31
        return 0
    fi

    start=`date +%s`
    {

        # Make dtb and dtbo
        cd kernel
        make O=$OUT -j $THREADS dtbs &>$LOGS/dtb.txt | tee $LOGS/dtb.txt 
        cd $CUR_DIR
        echo 33

        # Find dtb and copy to dtb.img
        find $OUT -name '*.dtb' -exec cp "{}" $BUILD/dtb.img \;
        echo 66

        # Build dtbo
        cd assets/libufdt-master-utils/src
        python mkdtboimg.py create $CUR_DIR/build/dtbo.img $BUILD/dtbo/*.dtbo
        cd $CUR_DIR
        echo 100

    } | whiptail --gauge "Running make -j $THREADS dtbs" 6 50 0
    end=`date +%s`



    whiptail --title "DTB Build Complete in $((end-start)) s" --msgbox "$(tail $LOGS/dtb.txt)" --scrolltext $MENU_HEIGHT $MENU_WIDTH
}

buildanykernel() {
    if [ "$DEVICECONFIG" == "" ]
    then
        whiptail --title "Configure kernel" --msgbox "Select device configuration" 7 31
        return 0
    fi

    start=`date +%s`
    {
        # Make anykernel zip
        mkdir -p $BUILD/temp
        cp -r assets/anykernel/* $BUILD/temp/
        echo 12

        # Copy all modules to anykernel dir
        if [ ! -z "$(ls $BUILD/modules/*.ko)" ]
        then
            cp $BUILD/modules/*.ko $BUILD/temp/modules/system/lib/modules
        fi
        echo 25

        # Copy kernel image to anykernel dir
        if [ -f "$BUILD/Image.gz" ]
        then
            cp $BUILD/Image.gz $BUILD/temp/Image.gz
        fi
        echo 37

        # Copy dtb
        if [ -f "$BUILD/dtb.img" ]
        then
            cp $BUILD/dtb.img $BUILD/temp/dtb
        fi
        echo 50

        # Copy dtbo
        if [ -f "$BUILD/dtbo.img" ]
        then
            cp $BUILD/dtbo.img $BUILD/temp/dtbo
        fi
        echo 62

        # Copy anykernel custom config
        if [ -f "$BUILD"/anykernelconfig.sh ]
        then
            rm $BUILD/temp/anykernel.sh
            cp $CUR_DIR/anykernelconfig.sh $BUILD/temp/anykernel.sh
        fi
        echo 75

        # Create zip
        if [ -f $BUILD/kernel.zip ]
        then
            rm $BUILD/kernel.zip
        fi
        echo 87

        cd $BUILD/temp/
        zip -r $BUILD/kernel.zip ./*
        cd $CUR_DIR
        echo 100

    } | whiptail --gauge "Running make -j $THREADS Image.gz" 6 50 0
    end=`date +%s`

}

clean() {
    rm -rf build
    rm -rf out
    rm -rf logs
}

mainmenu() 
{
    while [ "$MENU_RESPONSE" != "" ]
    do
        MENU_RESPONSE=$(whiptail --title "Android Kernel Builder - $THREADS threads $DEVICECONFIG" --menu "Choose an option" $MENU_HEIGHT $MENU_WIDTH $LIST_SIZE \
            "0." "Select Device Configuration" \
            "1." "Change thread number" \
            "2." "Configure Kernel with xconfig" \
            "3." "Build only Kernel" \
            "4." "Build only Modules" \
            "5." "Build only dtb.img and dtbo.img" \
            "6." "Build anykernel zip installable" \
            "7." "Clean all" 3>&1 1>&2 2>&3)

        case $MENU_RESPONSE in
            "0.")
                configmenu
                ;;
            "1.")
                threadsmenu
                ;;
            "2.")
                xconfigmenu
                ;;
            "3.")
                buildkernel
                ;;
            "4.")
                buildmodules
                ;;
            "5.")
                builddtb
                ;;
            "6.")
                buildanykernel
                ;;
            "7.")
                clean
                ;;
        esac
    done
}

mainmenu
exit