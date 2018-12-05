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
source scl_source enable devtoolset-7
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -e
trap 'lastcmd=$curcmd; curcmd=$BASH_COMMAND' DEBUG
trap 'errno=$?; print_cmd=$lastcmd; if [ $errno -ne 0 ]; then echo "\"${print_cmd}\" command failed with exit code $errno."; fi' EXIT
source "$BASE_DIR/common/common_options.sh"
parse_args "$@"

# Install pre-reqs.
if [ ${ROCM_LOCAL_INSTALL} = false ] || [ ${ROCM_INSTALL_PREREQS} = true ]; then
    echo "Installing software required to build the hipSPARSE."
    echo "You will need to have root privileges to do this."
    sudo yum -y install cmake pkgconfig git make wget
    if [ ${ROCM_INSTALL_PREREQS} = true ] && [ ${ROCM_FORCE_GET_CODE} = false ]; then
        exit 0
    fi
fi

# Set up source-code directory
if [ $ROCM_SAVE_SOURCE = true ]; then
    SOURCE_DIR=${ROCM_SOURCE_DIR}
    if [ ${ROCM_FORCE_GET_CODE} = true ] && [ -d ${SOURCE_DIR}/hipSPARSE ]; then
        rm -rf ${SOURCE_DIR}/hipSPARSE
    fi
    mkdir -p ${SOURCE_DIR}
else
    SOURCE_DIR=`mktemp -d`
fi
cd ${SOURCE_DIR}

# Download hipSPARSE
if [ ${ROCM_FORCE_GET_CODE} = true ] || [ ! -d ${SOURCE_DIR}/hipSPARSE ]; then
    # We require a new version of cmake to build the ROCr debug agent on CentOS.
    source "$BASE_DIR/common/get_updated_cmake.sh"
    get_cmake "${SOURCE_DIR}"
    git clone https://github.com/ROCmSoftwarePlatform/hipSPARSE.git
    cd hipSPARSE
    git checkout tags/v0.1.4.0
else
    echo "Skipping download of hipSPARSE, since ${SOURCE_DIR}/hipSPARSE already exists."
fi

if [ ${ROCM_FORCE_GET_CODE} = true ]; then
    echo "Finished downloading hipSPARSE. Exiting."
    exit 0
fi

cd ${SOURCE_DIR}/hipSPARSE
mkdir -p build/release
cd build/release
${SOURCE_DIR}/cmake/bin/cmake -DCMAKE_BUILD_TYPE=${ROCM_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=${ROCM_OUTPUT_DIR}/ -DCMAKE_PREFIX_PATH="${ROCM_INPUT_DIR}/hip/;${ROCM_INPUT_DIR}/hcc/" ../../
LD_LIBRARY_PATH=${ROCM_INPUT_DIR}/hsa/lib/:${ROCM_INPUT_DIR}/lib/:${LD_LIBRARY_PATH} make -j `nproc`
${ROCM_SUDO_COMMAND} make install

if [ $ROCM_SAVE_SOURCE = false ]; then
    rm -rf ${SOURCE_DIR}
fi
