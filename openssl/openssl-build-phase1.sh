#!/bin/bash
#
# This script downlaods and builds the Mac, Mac Catalyst and tvOS openSSL libraries with Bitcode enabled
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

buildCatalyst()
{
	ARCH=$1

	echo -e "${subbold}Building ${OPENSSL_VERSION} for Catalyst ${archbold}${ARCH}${dim}"

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"

	TARGET="darwin64-${ARCH}-cc"

	export PLATFORM="MacOSX"
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"

	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH} -target x86_64-apple-ios13.0-macabi"

	if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
		./Configure no-asm ${TARGET} -no-shared  --prefix="/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}" --openssldir="/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}.log"
	else
		./Configure no-asm ${TARGET} -no-shared  --openssldir="/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}" $CUSTOMCONFIG &> "/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}.log"
	fi

	if [[ "$OPENSSL_VERSION" = "openssl-1.1.1"* ]]; then
		sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} !" "Makefile"
	else
		sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} !" "Makefile"
	fi

	make -j4 >> "/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-catalyst-${ARCH}.log" 2>&1
	popd > /dev/null
}

# Prepare envrionment for build
echo -e "${bold}Setting Up Environment${dim}"
# rm -rf include/openssl/* lib/*

mkdir -p Catalyst/lib
mkdir -p iOS/lib
mkdir -p iOS-simulator/lib
mkdir -p Catalyst/include/openssl/
mkdir -p iOS/include/openssl/
mkdir -p iOS-simulator/include/openssl/

rm -rf /tmp/${OPENSSL_VERSION}-*
rm -rf /tmp/${OPENSSL_VERSION}-*.log

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

## Catalyst
if [ $catalyst == "1" ]; then
	echo -e "${bold}Building Catalyst libraries${dim}"
	buildCatalyst "x86_64"
	buildCatalyst "arm64"

	echo "  Copying headers and libraries"
	cp /tmp/${OPENSSL_VERSION}-catalyst-x86_64/include/openssl/* Catalyst/include/openssl/

	lipo \
		"/tmp/${OPENSSL_VERSION}-catalyst-x86_64/lib/libcrypto.a" \
		"/tmp/${OPENSSL_VERSION}-catalyst-arm64/lib/libcrypto.a" \
		-create -output Catalyst/lib/libcrypto.a

	lipo \
		"/tmp/${OPENSSL_VERSION}-catalyst-x86_64/lib/libssl.a" \
		"/tmp/${OPENSSL_VERSION}-catalyst-arm64/lib/libssl.a" \
		-create -output Catalyst/lib/libssl.a
fi

if [ $catalyst == "1" ]; then
libtool -no_warning_for_no_symbols -static -o openssl-ios-x86_64-maccatalyst.a Catalyst/lib/libcrypto.a Catalyst/lib/libssl.a
fi

#echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${OPENSSL_VERSION}-*
rm -rf ${OPENSSL_VERSION}

#reset trap
trap - INT TERM EXIT

#echo -e "${normal}Done"
