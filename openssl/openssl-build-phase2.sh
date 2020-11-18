#!/bin/bash
#
# This script downlaods and builds the iOS openSSL libraries with Bitcode enabled
#
# Author: Jason Cox, @jasonacox https://github.com/jasonacox/Build-OpenSSL-cURL
# Date: 2020-Aug-15
#

set -e

# Custom build options
CUSTOMCONFIG="enable-ssl-trace"

# Formatting
default="\033[39m"
white="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"

bold="\033[0m${green}\033[1m"
subbold="\033[0m${green}"
archbold="\033[0m${yellow}\033[1m"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# set trap to help debug build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/openssl*.log${alertdim}"; tail -3 /tmp/openssl*.log' INT TERM EXIT

IOS_MIN_SDK_VERSION="7.1"
IOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION=""
catalyst="0"

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<openssl version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-e] [-m] [-3] [-x] [-h]"
	echo
	echo "         -v   version of OpenSSL (default $OPENSSL_VERSION)"
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_MIN_SDK_VERSION)"
	echo "         -e   compile with engine support"
	echo "         -m   compile Mac Catalyst library [beta]"
	echo "         -3   compile with SSLv3 support"
	echo "         -x   disable color output"
	echo "         -h   show usage"
	echo
	trap - INT TERM EXIT
	exit 127
}

engine=0

while getopts "v:s:t:emx3h\?" o; do
	case "${o}" in
		v)
			OPENSSL_VERSION="openssl-${OPTARG}"
			;;
		s)
			IOS_SDK_VERSION="${OPTARG}"
			;;
		t)
			TVOS_SDK_VERSION="${OPTARG}"
			;;
		e)
			engine=1
			;;
		m)
			catalyst="1"
			;;
		x)
			bold=""
			subbold=""
			normal=""
			dim=""
			alert=""
			alertdim=""
			archbold=""
			;;
		3)
			CUSTOMCONFIG="enable-ssl3 enable-ssl3-method enable-ssl-trace"
			;;
		*)
			usage
			;;
	esac
done
shift $((OPTIND-1))

DEVELOPER=`xcode-select -print-path`

buildIOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
		#sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi

	if [[ "${ARCH}" == "arm64sim" ]]; then
		PLATFORM="iPhoneSimulator"
		ARCH="arm64"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"

	echo -e "${subbold}Building ${OPENSSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

	if [[ "${PLATFORM}" == "iPhoneSimulator" ]]; then
		TARGET="darwin-i386-cc"
		if [[ $ARCH == "x86_64" ]]; then
			TARGET="darwin64-x86_64-cc"
		fi
		if [[ $ARCH == "arm64" ]]; then
			TARGET="darwin64-arm64-cc"
		fi
		if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
			./Configure no-asm ${TARGET} -no-shared --prefix="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
		else
			./Configure no-asm ${TARGET} -no-shared --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
		fi
	else
		if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
			# export CC="${BUILD_TOOLS}/usr/bin/gcc -arch ${ARCH}"
			./Configure iphoneos-cross DSO_LDFLAGS=-fembed-bitcode --prefix="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" -no-shared --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
		else
			./Configure iphoneos-cross -no-shared --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
		fi
	fi
	# add -isysroot to CC=
	if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
		sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} !" "Makefile"
	else
		sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} !" "Makefile"
	fi

	make -j4 >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOSsim()
{
    ARCH=$1

    pushd . > /dev/null
    cd "${OPENSSL_VERSION}"

    PLATFORM="iPhoneSimulator"

    export $PLATFORM
    export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
    export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
    export BUILD_TOOLS="${DEVELOPER}"
    export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"

    echo -e "${subbold}Building ${OPENSSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

    if [[ "${PLATFORM}" == "iPhoneSimulator" ]]; then
        TARGET="darwin-i386-cc"
        if [[ $ARCH == "x86_64" ]]; then
            TARGET="darwin64-x86_64-cc"
        fi
        if [[ $ARCH == "arm64" ]]; then
            TARGET="darwin64-arm64-cc"
        fi
        if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
            ./Configure no-asm ${TARGET} -no-shared --prefix="/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}" --openssldir="/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
        else
            ./Configure no-asm ${TARGET} -no-shared --openssldir="/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}.log"
        fi
    else
        if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
            # export CC="${BUILD_TOOLS}/usr/bin/gcc -arch ${ARCH}"
            ./Configure iphoneos-cross DSO_LDFLAGS=-fembed-bitcode --prefix="/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}" -no-shared --openssldir="/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
        else
            ./Configure iphoneos-cross -no-shared --openssldir="/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}.log"
        fi
    fi
    # add -isysroot to CC=
    if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
        sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} !" "Makefile"
    else
        sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} !" "Makefile"
    fi

    make >> "/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}.log" 2>&1
    make install_sw >> "/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}.log" 2>&1
    make clean >> "/tmp/${OPENSSL_VERSION}-iOS-simulator-${ARCH}.log" 2>&1
    popd > /dev/null
}


#echo -e "${bold}Cleaning up${dim}"
#rm -rf include/openssl/* lib/*

mkdir -p Catalyst/lib
mkdir -p iOS/lib
mkdir -p iOS-simulator/lib
mkdir -p Catalyst/include/openssl/
mkdir -p iOS/include/openssl/
mkdir -p iOS-simulator/include/openssl/

rm -rf "/tmp/${OPENSSL_VERSION}-*"
rm -rf "/tmp/${OPENSSL_VERSION}-*.log"

rm -rf "${OPENSSL_VERSION}"

if [ ! -e ${OPENSSL_VERSION}.tar.gz ]; then
	echo "Downloading ${OPENSSL_VERSION}.tar.gz"
	curl -LO https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz
else
	echo "Using ${OPENSSL_VERSION}.tar.gz"
fi

if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
	echo "** Building OpenSSL 1.1.1 **"
else
	if [[ "$OPENSSL_VERSION" = "openssl-1.0."* ]]; then
		echo "** Building OpenSSL 1.0.x ** "
		echo -e "${alert}** WARNING: End of Life Version - Upgrade to 1.1.1 **${dim}"
	else
		echo -e "${alert}** WARNING: This build script has not been tested with $OPENSSL_VERSION **${dim}"
	fi
fi

echo "Unpacking openssl"
tar xfz "${OPENSSL_VERSION}.tar.gz"

if [ "$engine" == "1" ]; then
	echo "+ Activate Static Engine"
	sed -ie 's/\"engine/\"dynamic-engine/' ${OPENSSL_VERSION}/Configurations/15-ios.conf
fi

# Patch configuration to add macOS arm64 config - for openssl 1.1.1h
patch "${OPENSSL_VERSION}/Configurations/10-main.conf" 10-main.conf.patch >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1

echo -e "${bold}Building iOS libraries${dim}"
buildIOS "armv7"
buildIOS "arm64"

buildIOSsim "i386"
buildIOSsim "x86_64"
# buildIOSsim "arm64"

echo "  Copying headers and libraries"

# Build iOS Libraries
cp /tmp/${OPENSSL_VERSION}-iOS-arm64/include/openssl/* iOS/include/openssl/

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libcrypto.a" \
	-create -output iOS/lib/libcrypto.a

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libssl.a" \
	-create -output iOS/lib/libssl.a

# Build iOS Simulator Libraries
cp /tmp/${OPENSSL_VERSION}-iOS-simulator-x86_64/include/openssl/* iOS-simulator/include/openssl/

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-simulator-i386/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-simulator-x86_64/lib/libcrypto.a" \
	-create -output iOS-simulator/lib/libcrypto.a

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-simulator-x86_64/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-simulator-i386/lib/libssl.a" \
	-create -output iOS-simulator/lib/libssl.a

echo "  Creating combined OpenSSL libraries for iOS"
libtool -no_warning_for_no_symbols -static -o openssl-ios-armv7_arm64.a iOS/lib/libcrypto.a iOS/lib/libssl.a
libtool -no_warning_for_no_symbols -static -o openssl-ios-x86_64-simulator.a iOS-simulator/lib/libcrypto.a iOS-simulator/lib/libssl.a

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${OPENSSL_VERSION}-*
rm -rf ${OPENSSL_VERSION}

#reset trap
trap - INT TERM EXIT

#echo -e "${normal}Done"
