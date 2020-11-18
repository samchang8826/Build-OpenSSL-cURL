#!/bin/bash

# This script downlaods and builds the Mac, iOS and tvOS libcurl libraries with Bitcode enabled

# Credits:
#
# Felix Schwarz, IOSPIRIT GmbH, @@felix_schwarz.
#   https://gist.github.com/c61c0f7d9ab60f53ebb0.git
# Bochun Bai
#   https://github.com/sinofool/build-libcurl-ios
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL
# Preston Jennings
#   https://github.com/prestonj/Build-OpenSSL-cURL

set -e

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

# set trap to help debug any build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/curl*.log${alertdim}"; tail -3 /tmp/curl*.log' INT TERM EXIT

CURL_VERSION="curl-7.73.0"
IOS_SDK_VERSION=""
IOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
IPHONEOS_DEPLOYMENT_TARGET="9.0"
nohttp2="0"
catalyst="0"

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<curl version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-i ${dim}<iPhone target version>${normal}] [-b] [-m] [-x] [-n] [-h]"
    echo
	echo "         -v   version of curl (default $CURL_VERSION)"
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_MIN_SDK_VERSION)"
	echo "         -i   iPhone target version (default $IPHONEOS_DEPLOYMENT_TARGET)"
	echo "         -b   compile without bitcode"
	echo "         -n   compile with nghttp2"
	echo "         -m   compile Mac Catalyst library [beta]"
	echo "         -x   disable color output"
	echo "         -h   show usage"
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:t:i:nmbxh\?" o; do
    case "${o}" in
        v)
			CURL_VERSION="curl-${OPTARG}"
            ;;
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
        t)
	    	TVOS_SDK_VERSION="${OPTARG}"
            ;;
        i)
	    	IPHONEOS_DEPLOYMENT_TARGET="${OPTARG}"
            ;;
		n)
			nohttp2="1"
			;;
		m)
			catalyst="1"
			;;
		b)
			NOBITCODE="yes"
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
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

OPENSSL="${PWD}/../openssl"
DEVELOPER=`xcode-select -print-path`

# HTTP2 support
if [ $nohttp2 == "1" ]; then
	# nghttp2 will be in ../nghttp2/{Platform}/{arch}
	NGHTTP2="${PWD}/../nghttp2"
	# Check for pkg-config
	if ! (type "pkg-config" > /dev/null 2>&1 ) ; then
                PATH=$PATH:/tmp/pkg_config/bin
	fi
fi

if [ $nohttp2 == "1" ]; then
	echo "Building with HTTP2 Support (nghttp2)"
else
	echo "Building without HTTP2 Support (nghttp2)"
	NGHTTP2CFG=""
	NGHTTP2LIB=""
fi

buildCatalyst()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	cd "${CURL_VERSION}"


	PLATFORM="MacOSX"
	TARGET="x86_64-apple-ios13.0-macabi"

	if [[ "${BITCODE}" == "nobitcode" ]]; then
		CC_BITCODE_FLAG=""
	else
		CC_BITCODE_FLAG="-fembed-bitcode"
	fi

	if [ $nohttp2 == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Catalyst/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/Catalyst/${ARCH}/lib"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -target $TARGET ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/catalyst/lib ${NGHTTP2LIB}"

	echo -e "${subbold}Building ${CURL_VERSION} for $TARGET ${archbold}${ARCH}${dim} ${BITCODE}"

	./configure -prefix="/tmp/${CURL_VERSION}-catalyst-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/catalyst ${NGHTTP2CFG} --host="arm-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-catalyst-${ARCH}-${BITCODE}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-catalyst-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-catalyst-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null
}


buildIOS()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	cd "${CURL_VERSION}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
		SSLVARIANT="iOS-simulator"
	else
		PLATFORM="iPhoneOS"
		SSLVARIANT="iOS"
	fi

	if [[ "${BITCODE}" == "nobitcode" ]]; then
		CC_BITCODE_FLAG=""
	else
		CC_BITCODE_FLAG="-fembed-bitcode"
	fi

	if [ $nohttp2 == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/iOS/${ARCH}/lib"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"

	echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} ${BITCODE}"

	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/${SSLVARIANT}/lib ${NGHTTP2LIB}"

	if [[ "${ARCH}" == *"arm64"* || "${ARCH}" == "arm64e" ]]; then
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/${SSLVARIANT} ${NGHTTP2CFG} --host="arm-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else

		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/${SSLVARIANT} ${NGHTTP2CFG} --host="${ARCH}-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null
}

buildIOSsim()
{
    ARCH=$1
    BITCODE=$2

    pushd . > /dev/null
    cd "${CURL_VERSION}"

    PLATFORM="iPhoneSimulator"
    SSLVARIANT="iOS-simulator"

    if [[ "${BITCODE}" == "nobitcode" ]]; then
        CC_BITCODE_FLAG=""
    else
        CC_BITCODE_FLAG="-fembed-bitcode"
    fi

    if [ $nohttp2 == "1" ]; then
        NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS-simulator/${ARCH}"
        NGHTTP2LIB="-L${NGHTTP2}/iOS-simulator/${ARCH}/lib"
    fi

    export $PLATFORM
    export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
    export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
    export BUILD_TOOLS="${DEVELOPER}"
    export CC="${BUILD_TOOLS}/usr/bin/gcc"
    export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/${SSLVARIANT}/lib ${NGHTTP2LIB}"

    echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} ${BITCODE}"
    
    if [[ "${ARCH}" == *"arm64"* || "${ARCH}" == "arm64e" ]]; then
        # export LIBS=-lsocket
        #export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK}  ${CC_BITCODE_FLAG}"
        export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} ${CC_BITCODE_FLAG}"
		export LDFLAGS="$LDFLAGS -L${CROSS_TOP}/SDKs/${CROSS_SDK}/usr/lib"
        echo "---x---  ${CROSS_TOP}/SDKs/${CROSS_SDK}"
        echo "------- CC: ${CC}"
        echo "------- CFLAGS:  ${CFLAGS} "
        echo "------- LDFLAGS: ${LDFLAGS} "
        echo "        ./configure -prefix=/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE} --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/${SSLVARIANT} ${NGHTTP2CFG} --host=arm-apple-darwin"
        ./configure -prefix="/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/${SSLVARIANT} ${NGHTTP2CFG} --host="arm-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}.log"
    else
        export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"

        echo "        ./configure -prefix=/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE} --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/${SSLVARIANT} ${NGHTTP2CFG} --host=${ARCH}-apple-darwin"

        ./configure -prefix="/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/${SSLVARIANT} ${NGHTTP2CFG} --host="${ARCH}-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}.log"
    fi

    make -j8 >> "/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}.log" 2>&1
    make install >> "/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}.log" 2>&1
    make clean >> "/tmp/${CURL_VERSION}-iOS-simulator-${ARCH}-${BITCODE}.log" 2>&1
    popd > /dev/null
}

# Prepare envrionment for build
echo -e "${bold}Setting Up Environment${dim}"
rm -rf include/curl/* lib/*

mkdir -p lib
mkdir -p include/curl/

rm -rf /tmp/${CURL_VERSION}-*
rm -rf /tmp/${CURL_VERSION}-*.log

rm -rf "${CURL_VERSION}"

if [ ! -e ${CURL_VERSION}.tar.gz ]; then
	echo "Downloading ${CURL_VERSION}.tar.gz"
	curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
else
	echo "Using ${CURL_VERSION}.tar.gz"
fi

echo "Unpacking curl"
tar xfz "${CURL_VERSION}.tar.gz"

if [ $catalyst == "1" ]; then
echo -e "${bold}Building Catalyst libraries${dim}"
buildCatalyst "x86_64" "bitcode"
buildCatalyst "arm64" "bitcode"

lipo \
	"/tmp/${CURL_VERSION}-catalyst-x86_64-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-catalyst-arm64-bitcode/lib/libcurl.a" \
	-create -output lib/libcurl_Catalyst.a
fi

echo -e "${bold}Building iOS libraries (bitcode)${dim}"
buildIOS "armv7" "bitcode"
buildIOS "arm64" "bitcode"

lipo \
	"/tmp/${CURL_VERSION}-iOS-armv7-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-arm64-bitcode/lib/libcurl.a" \
	-create -output lib/libcurl_iOS.a

buildIOSsim "x86_64" "bitcode"

echo "  Copying headers"
cp /tmp/${CURL_VERSION}-iOS-simulator-x86_64-bitcode/include/curl/* include/curl/

buildIOSsim "i386" "bitcode"

# Build iOS Simulator Libraries
lipo \
	"/tmp/${CURL_VERSION}-iOS-simulator-i386-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-simulator-x86_64-bitcode/lib/libcurl.a" \
	-create -output lib/libcurl_iOS-simulator.a

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}

echo "Checking libraries"
xcrun -sdk iphoneos lipo -info lib/*.a

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
