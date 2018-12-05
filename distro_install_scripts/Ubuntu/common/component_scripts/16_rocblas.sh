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
    echo "Installing software required to build the rocBLAS."
    echo "You will need to have root privileges to do this."
    sudo apt -y install build-essential cmake pkg-config git make cmake-curses-gui python2.7 python-yaml gfortran libboost-program-options-dev
    if [ ${ROCM_INSTALL_PREREQS} = true ] && [ ${ROCM_FORCE_GET_CODE} = false ]; then
        exit 0
    fi
fi

# Set up source-code directory
if [ $ROCM_SAVE_SOURCE = true ]; then
    SOURCE_DIR=${ROCM_SOURCE_DIR}
    if [ ${ROCM_FORCE_GET_CODE} = true ] && [ -d ${SOURCE_DIR}/rocBLAS ]; then
        rm -rf ${SOURCE_DIR}/rocBLAS
    fi
    mkdir -p ${SOURCE_DIR}
else
    SOURCE_DIR=`mktemp -d`
fi
cd ${SOURCE_DIR}

# Download rocBLAS
if [ ${ROCM_FORCE_GET_CODE} = true ] || [ ! -d ${SOURCE_DIR}/rocBLAS ]; then
    git clone https://github.com/ROCmSoftwarePlatform/rocBLAS.git
    cd rocBLAS
    git checkout tags/v14.2.5
else
    echo "Skipping download of rocBLAS, since ${SOURCE_DIR}/rocBLAS already exists."
fi

if [ ${ROCM_FORCE_GET_CODE} = true ]; then
    echo "Finished downloading rocBLAS. Exiting."
    exit 0
fi

cd ${SOURCE_DIR}/rocBLAS
mkdir -p build/release
cd build/release
CXX=${ROCM_INPUT_DIR}/hcc/bin/hcc cmake -DCMAKE_BUILD_TYPE=${ROCM_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=${ROCM_OUTPUT_DIR}/ ../..
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

make -j ${NUM_BUILD_THREADS}
${ROCM_SUDO_COMMAND} make install

if [ ${ROCM_LOCAL_INSTALL} = false ]; then
    echo ${ROCM_OUTPUT_DIR}/lib | ${ROCM_SUDO_COMMAND} tee -a /etc/ld.so.conf.d/rocblas.conf
fi

if [ $ROCM_SAVE_SOURCE = false ]; then
    rm -rf ${SOURCE_DIR}
fi
