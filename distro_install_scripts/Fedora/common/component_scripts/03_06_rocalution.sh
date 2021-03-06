#!/bin/bash
###############################################################################
# Copyright (c) 2018 Advanced Micro Devices, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
###############################################################################
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -e
trap 'lastcmd=$curcmd; curcmd=$BASH_COMMAND' DEBUG
trap 'errno=$?; print_cmd=$lastcmd; if [ $errno -ne 0 ]; then echo "\"${print_cmd}\" command failed with exit code $errno."; fi' EXIT
source "$BASE_DIR/common/common_options.sh"
parse_args "$@"

# Install pre-reqs.
if [ ${ROCM_LOCAL_INSTALL} = false ] || [ ${ROCM_INSTALL_PREREQS} = true ]; then
    echo "Installing software required to build the rocALUTION."
    echo "You will need to have root privileges to do this."
    sudo dnf -y install cmake pkgconf-pkg-config git gcc-c++ boost-program-options rpm-build
    if [ ${ROCM_INSTALL_PREREQS} = true ] && [ ${ROCM_FORCE_GET_CODE} = false ]; then
        exit 0
    fi
fi

# Set up source-code directory
if [ $ROCM_SAVE_SOURCE = true ]; then
    SOURCE_DIR=${ROCM_SOURCE_DIR}
    if [ ${ROCM_FORCE_GET_CODE} = true ] && [ -d ${SOURCE_DIR}/rocALUTION ]; then
        rm -rf ${SOURCE_DIR}/rocALUTION
    fi
    mkdir -p ${SOURCE_DIR}
else
    SOURCE_DIR=`mktemp -d`
fi
cd ${SOURCE_DIR}

# Download rocALUTION
if [ ${ROCM_FORCE_GET_CODE} = true ] || [ ! -d ${SOURCE_DIR}/rocALUTION ]; then
    git clone https://github.com/ROCmSoftwarePlatform/rocALUTION.git
    cd rocALUTION
    git checkout ${ROCM_ROCALUTION_CHECKOUT}
else
    echo "Skipping download of rocALUTION, since ${SOURCE_DIR}/rocALUTION already exists."
fi

if [ ${ROCM_FORCE_GET_CODE} = true ]; then
    echo "Finished downloading rocALUTION. Exiting."
    exit 0
fi

cd ${SOURCE_DIR}/rocALUTION
mkdir -p build/release
# Fix some hard-coded locations in the CMake files
git checkout ${SOURCE_DIR}/rocALUTION/cmake/Dependencies.cmake
sed -i 's#/opt/rocm/bin/hcc#${HIP_HCC_EXECUTABLE} -DCMAKE_PREFIX_PATH='"${ROCM_INPUT_DIR}"' -DCMAKE_MODULE_PATH='"${ROCM_INPUT_DIR}"'/hip/cmake/#' ${SOURCE_DIR}/rocALUTION/cmake/Dependencies.cmake
git checkout ${SOURCE_DIR}/rocALUTION/src/CMakeLists.txt
sed -i "s#-O3#-O3 -I${ROCM_INPUT_DIR}/include/ -I${SOURCE_DIR}/rocALUTION/build/release/rocPRIM/hipcub/include -I${SOURCE_DIR}/rocALUTION/build/release/rocPRIM/include/#" ${SOURCE_DIR}/rocALUTION/src/CMakeLists.txt
sed -i "s#-g#-g -I${ROCM_INPUT_DIR}/include/ -I${SOURCE_DIR}/rocALUTION/build/release/rocPRIM/hipcub/include -I${SOURCE_DIR}/rocALUTION/build/release/rocPRIM/include/#" ${SOURCE_DIR}/rocALUTION/src/CMakeLists.txt

cd build/release
HIP_PLATFORM=hcc CXX=${ROCM_INPUT_DIR}/hcc/bin/hcc cmake -DCPACK_PACKAGING_INSTALL_PREFIX=${ROCM_OUTPUT_DIR}/ -DCPACK_GENERATOR=RPM ${ROCM_CPACK_RPM_PERMISSIONS} -DCMAKE_BUILD_TYPE=${ROCM_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=${ROCM_OUTPUT_DIR}/ -DCMAKE_PREFIX_PATH="${ROCM_INPUT_DIR}/hip/;${ROCM_INPUT_DIR}/hcc/" ../../
# Linking can take a large amount of memory, and it will fail if you do not
# have enough memory available per thread. As such, this # logic limits the
# number of build threads in response to the amount of available memory on
# the system.
MEM_AVAIL=`cat /proc/meminfo | grep MemTotal | awk {'print $2'}`
AVAIL_THREADS=`nproc`

# Give about 4 GB to each building thread
MAX_THREADS=`echo $(( ${MEM_AVAIL} / $(( 1024 * 1024 * 4 )) ))`
if [ ${MAX_THREADS} -lt ${AVAIL_THREADS} ]; then
    NUM_BUILD_THREADS=${MAX_THREADS}
else
    NUM_BUILD_THREADS=${AVAIL_THREADS}
fi
if [ ${NUM_BUILD_THREADS} -lt 1 ]; then
    NUM_BUILD_THREADS=1
fi

LD_LIBRARY_PATH=${ROCM_INPUT_DIR}/lib/:${ROCM_INPUT_DIR}/hsa/lib/ HCC_HOME=${ROCM_INPUT_DIR}/hcc/ HSA_PATH=${ROCM_INPUT_DIR}/hsa/ ROCM_PATH=${ROCM_INPUT_DIR}/ HIP_PLATFORM=hcc make -j ${NUM_BUILD_THREADS}

if [ ${ROCM_FORCE_BUILD_ONLY} = true ]; then
    echo "Finished building rocALUTION. Exiting."
    exit 0
fi

if [ ${ROCM_FORCE_PACKAGE} = true ]; then
    make package
    echo "Copying `ls -1 rocalution-*.rpm` to ${ROCM_PACKAGE_DIR}"
    mkdir -p ${ROCM_PACKAGE_DIR}
    cp ./rocalution-*.rpm ${ROCM_PACKAGE_DIR}
    if [ ${ROCM_LOCAL_INSTALL} = false ]; then
        ROCM_PKG_IS_INSTALLED=`rpm -qa | grep rocalution | wc -l`
        if [ ${ROCM_PKG_IS_INSTALLED} -gt 0 ]; then
            PKG_NAME=`rpm -qa | grep rocalution | head -n 1`
            sudo rpm -e --nodeps ${PKG_NAME}
        fi
        sudo rpm -i ./rocalution-*.rpm
    fi
else
    ${ROCM_SUDO_COMMAND} make install

    if [ ${ROCM_LOCAL_INSTALL} = false ]; then
        echo ${ROCM_OUTPUT_DIR}/lib | ${ROCM_SUDO_COMMAND} tee -a /etc/ld.so.conf.d/rocalution.conf
    fi
fi

if [ $ROCM_SAVE_SOURCE = false ]; then
    rm -rf ${SOURCE_DIR}
fi
